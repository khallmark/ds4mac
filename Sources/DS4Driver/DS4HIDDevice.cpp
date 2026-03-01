// DS4HIDDevice.cpp — DriverKit DualShock 4 HID device implementation
// This driver matches USB DS4 controllers, polls for input reports via
// interrupt IN pipe, parses them, and forwards to IOHIDFamily so that
// GameController.framework sees the device as a GCDualShockGamepad.
//
// Reference: docs/10-macOS-Driver-Architecture.md Section 3
//            docs/04-DS4-USB-Protocol.md Section 2.1 (input), Section 3 (output)

#include <os/log.h>

#include <DriverKit/IOLib.h>
#include <DriverKit/IOMemoryDescriptor.h>
#include <DriverKit/IOBufferMemoryDescriptor.h>
#include <DriverKit/OSData.h>
#include <DriverKit/OSDictionary.h>
#include <DriverKit/OSNumber.h>
#include <DriverKit/OSString.h>

#include <USBDriverKit/IOUSBHostDevice.h>
#include <USBDriverKit/IOUSBHostInterface.h>
#include <USBDriverKit/IOUSBHostPipe.h>
#include <USBDriverKit/AppleUSBDescriptorParsing.h>

#include <HIDDriverKit/IOUserHIDDevice.h>
#include <HIDDriverKit/HIDDriverKit.h>

#include "DS4HIDDevice.h"
#include "DS4ReportDescriptor.h"
#include "DS4Protocol.h"

#define LOG_PREFIX "DS4Mac: "

// MARK: - Instance Variables

struct DS4HIDDevice_IVars {
    IOUSBHostInterface           * interface;
    IOUSBHostPipe                * inPipe;
    IOUSBHostPipe                * outPipe;
    IOBufferMemoryDescriptor     * inBuffer;
    IOBufferMemoryDescriptor     * outBuffer;
    OSAction                     * inputAction;

    DS4InputState                  inputState;
    DS4OutputState                 outputState;
    DS4CalibrationData             calibration;

    uint16_t                       productID;
    uint8_t                        lastBatteryLevel;
    bool                           lastCableConnected;
};

// MARK: - Lifecycle

bool DS4HIDDevice::init()
{
    if (!super::init()) {
        return false;
    }

    ivars = IONewZero(DS4HIDDevice_IVars, 1);
    if (!ivars) {
        return false;
    }

    ds4_input_state_init(&ivars->inputState);
    ds4_output_state_init(&ivars->outputState);
    ds4_calibration_data_init(&ivars->calibration);
    ivars->lastBatteryLevel = 0xFF;    // sentinel to force first update
    ivars->lastCableConnected = false;

    os_log(OS_LOG_DEFAULT, LOG_PREFIX "init");
    return true;
}

kern_return_t DS4HIDDevice::Start_Impl(IOService * provider)
{
    kern_return_t ret;

    ret = Start(provider, SUPERDISPATCH);
    if (ret != kIOReturnSuccess) {
        os_log(OS_LOG_DEFAULT, LOG_PREFIX "super::Start failed: 0x%x", ret);
        return ret;
    }

    // Cast provider to IOUSBHostInterface — this is what our IOKitPersonality matches
    ivars->interface = OSDynamicCast(IOUSBHostInterface, provider);
    if (!ivars->interface) {
        os_log(OS_LOG_DEFAULT, LOG_PREFIX "provider is not IOUSBHostInterface");
        return kIOReturnNoDevice;
    }
    ivars->interface->retain();

    // Read the product ID from the provider's properties so that
    // newDeviceDescription() returns the correct PID for V1 vs V2.
    // DriverKit's IOService only has CopyProperties (all props), not CopyProperty (single key).
    OSDictionary * props = nullptr;
    if (provider->CopyProperties(&props) == kIOReturnSuccess && props) {
        auto pidNum = OSDynamicCast(OSNumber, props->getObject("idProduct"));
        if (pidNum) {
            ivars->productID = static_cast<uint16_t>(pidNum->unsigned32BitValue() & 0xFFFF);
            os_log(OS_LOG_DEFAULT, LOG_PREFIX "Matched product ID: 0x%04x", ivars->productID);
        }
        OSSafeReleaseNULL(props);
    }
    if (ivars->productID == 0) {
        ivars->productID = DS4_V1_PRODUCT_ID;
    }

    // Configure USB endpoints and start polling
    ret = configureDevice();
    if (ret != kIOReturnSuccess) {
        os_log(OS_LOG_DEFAULT, LOG_PREFIX "configureDevice failed: 0x%x", ret);
        return ret;
    }

    // Read IMU calibration from Feature Report 0x02 (non-fatal if it fails)
    ret = readCalibrationData();
    if (ret != kIOReturnSuccess) {
        os_log(OS_LOG_DEFAULT, LOG_PREFIX "Calibration read failed (non-fatal): 0x%x — using BMI055 nominal values", ret);
    }

    ret = startInputPolling();
    if (ret != kIOReturnSuccess) {
        os_log(OS_LOG_DEFAULT, LOG_PREFIX "startInputPolling failed: 0x%x", ret);
        return ret;
    }

    // Register with IOHIDFamily — this makes the DS4 visible as a HID device
    RegisterService();

    os_log(OS_LOG_DEFAULT, LOG_PREFIX "DualShock 4 driver started successfully");
    return kIOReturnSuccess;
}

kern_return_t DS4HIDDevice::Stop_Impl(IOService * provider)
{
    os_log(OS_LOG_DEFAULT, LOG_PREFIX "DualShock 4 driver stopping");

    // Cancel any pending async I/O
    if (ivars->inPipe) {
        ivars->inPipe->Abort(0, kIOReturnAborted, nullptr);
    }

    // Release resources
    OSSafeReleaseNULL(ivars->inputAction);
    OSSafeReleaseNULL(ivars->inBuffer);
    OSSafeReleaseNULL(ivars->outBuffer);
    OSSafeReleaseNULL(ivars->inPipe);
    OSSafeReleaseNULL(ivars->outPipe);
    OSSafeReleaseNULL(ivars->interface);

    return Stop(provider, SUPERDISPATCH);
}

void DS4HIDDevice::free()
{
    os_log(OS_LOG_DEFAULT, LOG_PREFIX "free");
    IOSafeDeleteNULL(ivars, DS4HIDDevice_IVars, 1);
    super::free();
}

// MARK: - HID Device Description

OSDictionary * DS4HIDDevice::newDeviceDescription()
{
    auto dict = OSDictionary::withCapacity(8);
    if (!dict) {
        return nullptr;
    }

    // These properties allow IOHIDFamily and GameController.framework to
    // identify this device as a Sony DualShock 4 (GCDualShockGamepad).
    uint32_t pid = (ivars && ivars->productID != 0)
                     ? ivars->productID : DS4_V1_PRODUCT_ID;
    auto vendorID  = OSNumber::withNumber(DS4_VENDOR_ID, 32);
    auto productID = OSNumber::withNumber(pid, 32);
    auto transport = OSString::withCString("USB");
    auto manufacturer = OSString::withCString("Sony Computer Entertainment");
    auto product   = OSString::withCString("Wireless Controller");

    // IOUserClientClass tells the DriverKit runtime which class to instantiate
    // when the companion app calls IOServiceOpen() on this service.
    auto userClientClass = OSString::withCString("DS4UserClient");

    if (vendorID)        { dict->setObject("VendorID", vendorID);               vendorID->release(); }
    if (productID)       { dict->setObject("ProductID", productID);             productID->release(); }
    if (transport)       { dict->setObject("Transport", transport);             transport->release(); }
    if (manufacturer)    { dict->setObject("Manufacturer", manufacturer);       manufacturer->release(); }
    if (product)         { dict->setObject("Product", product);                 product->release(); }
    if (userClientClass) { dict->setObject("IOUserClientClass", userClientClass); userClientClass->release(); }

    return dict;
}

OSData * DS4HIDDevice::newReportDescriptor()
{
    // Return the HID report descriptor that describes the DS4 gamepad layout.
    // This is the same descriptor used by the original hardware, so
    // GameController.framework recognizes it as GCDualShockGamepad.
    return OSData::withBytes(DS4ReportDescriptor, DS4ReportDescriptorSize);
}

// MARK: - USB Configuration

kern_return_t DS4HIDDevice::configureDevice()
{
    kern_return_t ret;

    // Open the USB interface for exclusive access
    ret = ivars->interface->Open(this, 0, nullptr);
    if (ret != kIOReturnSuccess) {
        os_log(OS_LOG_DEFAULT, LOG_PREFIX "Failed to open interface: 0x%x", ret);
        return ret;
    }

    // Get the configuration and interface descriptors to find endpoints.
    // DS4 USB interface 0 has:
    //   - Endpoint 0x84 (IN, interrupt)  — input reports at ~250 Hz
    //   - Endpoint 0x03 (OUT, interrupt) — output reports (LED, rumble)
    const IOUSBConfigurationDescriptor * configDesc =
        ivars->interface->CopyConfigurationDescriptor();
    if (!configDesc) {
        os_log(OS_LOG_DEFAULT, LOG_PREFIX "Failed to get configuration descriptor");
        return kIOReturnNotFound;
    }

    const IOUSBInterfaceDescriptor * ifaceDesc =
        ivars->interface->GetInterfaceDescriptor(configDesc);
    if (!ifaceDesc) {
        os_log(OS_LOG_DEFAULT, LOG_PREFIX "Failed to get interface descriptor");
        IOFree(const_cast<IOUSBConfigurationDescriptor *>(configDesc),
               configDesc->wTotalLength);
        return kIOReturnNotFound;
    }

    // Iterate endpoint descriptors within this interface
    const IOUSBDescriptorHeader * current = nullptr;
    while (true) {
        current = IOUSBGetNextAssociatedDescriptorWithType(
            configDesc,
            reinterpret_cast<const IOUSBDescriptorHeader *>(ifaceDesc),
            current,
            kIOUSBDescriptorTypeEndpoint);
        if (!current) {
            break;
        }

        auto epDesc = reinterpret_cast<const IOUSBEndpointDescriptor *>(current);
        uint8_t epAddr = epDesc->bEndpointAddress;
        uint8_t epDir  = epAddr & 0x80;  // bit 7: 1=IN, 0=OUT
        uint8_t epType = epDesc->bmAttributes & 0x03;  // bits 1:0

        if (epType == kIOUSBEndpointTypeInterrupt) {
            IOUSBHostPipe * pipe = nullptr;
            ret = ivars->interface->CopyPipe(epAddr, &pipe);
            if (ret == kIOReturnSuccess && pipe) {
                if (epDir) {
                    // Interrupt IN — input reports
                    ivars->inPipe = pipe;
                    os_log(OS_LOG_DEFAULT, LOG_PREFIX "Found interrupt IN pipe: 0x%02x", epAddr);
                } else {
                    // Interrupt OUT — output reports
                    ivars->outPipe = pipe;
                    os_log(OS_LOG_DEFAULT, LOG_PREFIX "Found interrupt OUT pipe: 0x%02x", epAddr);
                }
            }
        }
    }

    IOFree(const_cast<IOUSBConfigurationDescriptor *>(configDesc),
           configDesc->wTotalLength);

    if (!ivars->inPipe) {
        os_log(OS_LOG_DEFAULT, LOG_PREFIX "No interrupt IN pipe found");
        return kIOReturnNotFound;
    }

    // Allocate input buffer for 64-byte USB reports
    ret = IOBufferMemoryDescriptor::Create(
        kIOMemoryDirectionIn,
        DS4_USB_INPUT_REPORT_SIZE,
        0,
        &ivars->inBuffer
    );
    if (ret != kIOReturnSuccess) {
        os_log(OS_LOG_DEFAULT, LOG_PREFIX "Failed to create input buffer: 0x%x", ret);
        return ret;
    }

    // Allocate output buffer for 32-byte USB output reports
    ret = IOBufferMemoryDescriptor::Create(
        kIOMemoryDirectionOut,
        DS4_USB_OUTPUT_REPORT_SIZE,
        0,
        &ivars->outBuffer
    );
    if (ret != kIOReturnSuccess) {
        os_log(OS_LOG_DEFAULT, LOG_PREFIX "Failed to create output buffer: 0x%x", ret);
        return ret;
    }

    os_log(OS_LOG_DEFAULT, LOG_PREFIX "Device configured successfully");
    return kIOReturnSuccess;
}

// MARK: - Input Report Polling

kern_return_t DS4HIDDevice::startInputPolling()
{
    kern_return_t ret;

    // Create the completion action for async reads.
    // IIG generates CreateActioninputReportComplete (lowercase 'i') from the
    // method name inputReportComplete declared in the .iig file.
    ret = CreateActioninputReportComplete(
        sizeof(void *),  // action size
        &ivars->inputAction
    );
    if (ret != kIOReturnSuccess) {
        os_log(OS_LOG_DEFAULT, LOG_PREFIX "Failed to create input action: 0x%x", ret);
        return ret;
    }

    // Schedule the first async read on the interrupt IN pipe
    ret = ivars->inPipe->AsyncIO(
        ivars->inBuffer,
        DS4_USB_INPUT_REPORT_SIZE,
        ivars->inputAction,
        0  // no timeout
    );
    if (ret != kIOReturnSuccess) {
        os_log(OS_LOG_DEFAULT, LOG_PREFIX "Failed to start async IO: 0x%x", ret);
        return ret;
    }

    os_log(OS_LOG_DEFAULT, LOG_PREFIX "Input polling started");
    return kIOReturnSuccess;
}

// MARK: - Input Report Completion Callback

void DS4HIDDevice::inputReportComplete_Impl(OSAction * action,
                                              IOReturn   status,
                                              uint32_t   actualByteCount,
                                              uint64_t   completionTimestamp)
{
    if (status != kIOReturnSuccess) {
        if (status == kIOReturnAborted) {
            // Normal shutdown — don't reschedule
            os_log(OS_LOG_DEFAULT, LOG_PREFIX "Input polling aborted (shutdown)");
            return;
        }
        os_log(OS_LOG_DEFAULT, LOG_PREFIX "Input report error: 0x%x", status);
        // Try to continue polling despite errors
    }

    if (actualByteCount >= DS4_USB_INPUT_REPORT_SIZE && ivars->inBuffer) {
        // Access the buffer bytes directly via GetAddressRange
        IOAddressSegment range = {};
        kern_return_t ret = ivars->inBuffer->GetAddressRange(&range);

        if (ret == kIOReturnSuccess && range.address && range.length >= DS4_USB_INPUT_REPORT_SIZE) {
            const uint8_t * data = reinterpret_cast<const uint8_t *>(range.address);
            processInputReport(data, static_cast<uint32_t>(range.length));

            // Forward the raw report to IOHIDFamily so GCController sees it
            handleReport(completionTimestamp,
                         ivars->inBuffer,
                         static_cast<uint32_t>(range.length),
                         kIOHIDReportTypeInput,
                         0);
        }
    }

    // Reschedule the next async read to keep polling
    if (ivars->inPipe && ivars->inBuffer && ivars->inputAction) {
        kern_return_t ret = ivars->inPipe->AsyncIO(
            ivars->inBuffer,
            DS4_USB_INPUT_REPORT_SIZE,
            ivars->inputAction,
            0
        );
        if (ret != kIOReturnSuccess) {
            os_log(OS_LOG_DEFAULT, LOG_PREFIX "Failed to reschedule input: 0x%x", ret);
        }
    }
}

// MARK: - Report Processing

void DS4HIDDevice::processInputReport(const uint8_t * data, uint32_t length)
{
    // Parse the USB input report into our internal state struct
    ds4_parse_usb_input_report(data, length, &ivars->inputState);

    // Update IORegistry battery properties when level or charging state changes
    if (ivars->inputState.battery.level != ivars->lastBatteryLevel ||
        ivars->inputState.battery.cableConnected != ivars->lastCableConnected) {
        updateBatteryProperties();
        ivars->lastBatteryLevel = ivars->inputState.battery.level;
        ivars->lastCableConnected = ivars->inputState.battery.cableConnected;
    }
}

kern_return_t DS4HIDDevice::sendOutputReport(const uint8_t * data, uint32_t length)
{
    if (!ivars->outPipe || !ivars->outBuffer) {
        return kIOReturnNotReady;
    }

    uint32_t writeLen = (length < DS4_USB_OUTPUT_REPORT_SIZE)
                          ? length : DS4_USB_OUTPUT_REPORT_SIZE;

    // Access output buffer directly via GetAddressRange and copy report data
    IOAddressSegment range = {};
    kern_return_t ret = ivars->outBuffer->GetAddressRange(&range);
    if (ret != kIOReturnSuccess || !range.address) {
        return ret;
    }

    memcpy(reinterpret_cast<void *>(range.address), data, writeLen);

    // Send synchronously via the interrupt OUT pipe
    uint32_t bytesTransferred = 0;
    ret = ivars->outPipe->IO(ivars->outBuffer, writeLen, &bytesTransferred, 0);
    if (ret != kIOReturnSuccess) {
        os_log(OS_LOG_DEFAULT, LOG_PREFIX "Output report failed: 0x%x", ret);
    }

    return ret;
}

// MARK: - State Accessor

bool DS4HIDDevice::copyInputState(void * outBuffer, uint32_t bufferSize)
{
    if (!outBuffer || bufferSize < sizeof(DS4InputState)) {
        return false;
    }
    // TODO: Add os_unfair_lock if contention with inputReportComplete becomes an issue.
    // For now, this copies a snapshot that may be mid-update — acceptable for
    // diagnostic reads via IOUserClient (getInputState/getBatteryState selectors).
    memcpy(outBuffer, &ivars->inputState, sizeof(DS4InputState));
    return true;
}

// MARK: - IMU Calibration

kern_return_t DS4HIDDevice::readCalibrationData()
{
    if (!ivars->interface) {
        return kIOReturnNotReady;
    }

    // Allocate a buffer for the 37-byte calibration feature report
    IOBufferMemoryDescriptor * calBuffer = nullptr;
    kern_return_t ret = IOBufferMemoryDescriptor::Create(
        kIOMemoryDirectionIn,
        DS4_CALIBRATION_REPORT_SIZE,
        0,
        &calBuffer
    );
    if (ret != kIOReturnSuccess || !calBuffer) {
        os_log(OS_LOG_DEFAULT, LOG_PREFIX "Failed to create calibration buffer: 0x%x", ret);
        return ret;
    }

    // USB HID GET_REPORT control transfer for Feature Report 0x02
    // bmRequestType = 0xA1 (device-to-host, class, interface)
    // bRequest = 0x01 (GET_REPORT)
    // wValue = 0x0302 (report type Feature=0x03 << 8 | report ID 0x02)
    // wIndex = 0 (interface number)
    // wLength = 37
    uint16_t bytesTransferred = 0;
    ret = ivars->interface->DeviceRequest(
        /* bmRequestType */ 0xA1,
        /* bRequest      */ 0x01,
        /* wValue        */ 0x0302,
        /* wIndex        */ 0,
        /* wLength       */ DS4_CALIBRATION_REPORT_SIZE,
        /* dataBuffer    */ calBuffer,
        /* bytesTransferred */ &bytesTransferred,
        /* completionTimeout */ 5000  // 5 second timeout
    );

    if (ret != kIOReturnSuccess) {
        os_log(OS_LOG_DEFAULT, LOG_PREFIX "DeviceRequest for calibration failed: 0x%x", ret);
        OSSafeReleaseNULL(calBuffer);
        return ret;
    }

    if (bytesTransferred < DS4_CALIBRATION_REPORT_SIZE) {
        os_log(OS_LOG_DEFAULT, LOG_PREFIX "Calibration report too short: %u bytes", bytesTransferred);
        OSSafeReleaseNULL(calBuffer);
        return kIOReturnUnderrun;
    }

    // Extract buffer bytes and parse
    IOAddressSegment range = {};
    ret = calBuffer->GetAddressRange(&range);
    if (ret == kIOReturnSuccess && range.address && range.length >= DS4_CALIBRATION_REPORT_SIZE) {
        const uint8_t * data = reinterpret_cast<const uint8_t *>(range.address);
        if (ds4_parse_usb_calibration(data, DS4_CALIBRATION_REPORT_SIZE, &ivars->calibration)) {
            os_log(OS_LOG_DEFAULT, LOG_PREFIX "Calibration loaded (valid=%d, pitchBias=%d, yawBias=%d, rollBias=%d)",
                   ivars->calibration.isValid,
                   ivars->calibration.gyroPitchBias,
                   ivars->calibration.gyroYawBias,
                   ivars->calibration.gyroRollBias);
        } else {
            os_log(OS_LOG_DEFAULT, LOG_PREFIX "Calibration parse failed");
        }
    }

    OSSafeReleaseNULL(calBuffer);
    return kIOReturnSuccess;
}

bool DS4HIDDevice::copyCalibrationData(void * outBuffer, uint32_t bufferSize)
{
    if (!outBuffer || bufferSize < sizeof(DS4CalibrationData)) {
        return false;
    }
    memcpy(outBuffer, &ivars->calibration, sizeof(DS4CalibrationData));
    return true;
}

bool DS4HIDDevice::copyCalibratedIMU(void * outBuffer, uint32_t bufferSize)
{
    if (!outBuffer || bufferSize < sizeof(DS4CalibratedIMU)) {
        return false;
    }
    DS4CalibratedIMU calibrated;
    ds4_calibrate_imu(&ivars->inputState.imu, &ivars->calibration, &calibrated);
    memcpy(outBuffer, &calibrated, sizeof(DS4CalibratedIMU));
    return true;
}

// MARK: - Battery IORegistry Properties

void DS4HIDDevice::updateBatteryProperties()
{
    uint8_t level = ivars->inputState.battery.level;
    bool charging = ivars->inputState.battery.cableConnected;
    uint32_t maxVal = charging ? 11 : 8;
    uint32_t percent = (level * 100) / (maxVal > 0 ? maxVal : 1);
    if (percent > 100) percent = 100;

    auto percentNum = OSNumber::withNumber(percent, 32);
    auto chargingNum = OSNumber::withNumber(charging ? 1 : 0, 32);

    if (percentNum) {
        SetProperty("BatteryPercent", percentNum);
        percentNum->release();
    }
    if (chargingNum) {
        SetProperty("BatteryCharging", chargingNum);
        chargingNum->release();
    }

    os_log(OS_LOG_DEFAULT, LOG_PREFIX "Battery: %u%% %s",
           percent, charging ? "(charging)" : "(wireless)");
}

// MARK: - HID Report Overrides

kern_return_t DS4HIDDevice::getReport(IOMemoryDescriptor * report,
                                        IOHIDReportType      reportType,
                                        IOOptionBits         options,
                                        uint32_t             completionTimeout,
                                        OSAction           * action)
{
    // Forward feature report requests to the USB device
    // This is used for calibration data (Report ID 0x02), etc.
    return super::getReport(report, reportType, options, completionTimeout, action);
}

kern_return_t DS4HIDDevice::setReport(IOMemoryDescriptor * report,
                                        IOHIDReportType      reportType,
                                        IOOptionBits         options,
                                        uint32_t             completionTimeout,
                                        OSAction           * action)
{
    if (reportType == kIOHIDReportTypeOutput && report) {
        // For output reports, map the descriptor to read the bytes
        IOMemoryMap * map = nullptr;
        kern_return_t ret = report->CreateMapping(0, 0, 0, 0, 0, &map);
        if (ret == kIOReturnSuccess && map) {
            uint64_t address = map->GetAddress();
            uint64_t length  = map->GetLength();
            if (address && length > 0) {
                const uint8_t * data = reinterpret_cast<const uint8_t *>(address);
                sendOutputReport(data, static_cast<uint32_t>(length));
            }
            map->release();
        }
        return kIOReturnSuccess;
    }

    return super::setReport(report, reportType, options, completionTimeout, action);
}
