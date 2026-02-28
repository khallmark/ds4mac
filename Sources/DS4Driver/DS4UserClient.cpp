// DS4UserClient.cpp — IOUserClient implementation for DS4Mac companion app
// Handles external method calls from the companion app to control
// the DualShock 4 light bar, rumble motors, and query input state.
//
// Reference: docs/10-macOS-Driver-Architecture.md Section 3 (IOUserClient)

#include <os/log.h>

#include <DriverKit/IOLib.h>
#include <DriverKit/IOUserClient.h>
#include <DriverKit/OSData.h>

#include "DS4UserClient.h"
#include "DS4HIDDevice.h"
#include "DS4Protocol.h"

#define LOG_PREFIX "DS4Mac-UC: "

// MARK: - Selector IDs (must match companion app's DriverCommunication.swift)

enum DS4UserClientSelector : uint64_t {
    kDS4SelectorSetLightBar    = 0,
    kDS4SelectorSetRumble      = 1,
    kDS4SelectorGetInputState  = 2,
    kDS4SelectorGetBatteryState = 3,
    kDS4SelectorCount          = 4,
};

// MARK: - Instance Variables

struct DS4UserClient_IVars {
    DS4HIDDevice * device;
};

// MARK: - Static Method Handlers

static kern_return_t sSetLightBar(OSObject * target, void * reference,
                                    IOUserClientMethodArguments * arguments)
{
    // Expect 3 scalar inputs: R, G, B (0-255 each)
    if (arguments->scalarInputCount < 3) {
        return kIOReturnBadArgument;
    }

    uint8_t r = (uint8_t)(arguments->scalarInput[0] & 0xFF);
    uint8_t g = (uint8_t)(arguments->scalarInput[1] & 0xFF);
    uint8_t b = (uint8_t)(arguments->scalarInput[2] & 0xFF);

    os_log(OS_LOG_DEFAULT, LOG_PREFIX "setLightBar(%u, %u, %u)", r, g, b);

    // Build and send output report with LED color
    DS4OutputState outputState;
    ds4_output_state_init(&outputState);
    outputState.ledRed   = r;
    outputState.ledGreen = g;
    outputState.ledBlue  = b;

    uint8_t report[DS4_USB_OUTPUT_REPORT_SIZE];
    ds4_build_usb_output_report(&outputState, report);

    // TODO: Send report via DS4HIDDevice when cross-referencing is set up
    // For now, the device reference will be populated in Start()

    return kIOReturnSuccess;
}

static kern_return_t sSetRumble(OSObject * target, void * reference,
                                  IOUserClientMethodArguments * arguments)
{
    // Expect 2 scalar inputs: heavy motor, light motor (0-255 each)
    if (arguments->scalarInputCount < 2) {
        return kIOReturnBadArgument;
    }

    uint8_t heavy = (uint8_t)(arguments->scalarInput[0] & 0xFF);
    uint8_t light = (uint8_t)(arguments->scalarInput[1] & 0xFF);

    os_log(OS_LOG_DEFAULT, LOG_PREFIX "setRumble(%u, %u)", heavy, light);

    DS4OutputState outputState;
    ds4_output_state_init(&outputState);
    outputState.rumbleHeavy = heavy;
    outputState.rumbleLight = light;

    uint8_t report[DS4_USB_OUTPUT_REPORT_SIZE];
    ds4_build_usb_output_report(&outputState, report);

    // TODO: Send report via DS4HIDDevice

    return kIOReturnSuccess;
}

static kern_return_t sGetInputState(OSObject * target, void * reference,
                                      IOUserClientMethodArguments * arguments)
{
    // Return input state as struct output
    if (!arguments->structureOutput || arguments->structureOutputSize < sizeof(DS4InputState)) {
        return kIOReturnBadArgument;
    }

    // TODO: Copy current input state from DS4HIDDevice
    DS4InputState state;
    ds4_input_state_init(&state);
    memcpy(arguments->structureOutput->getBytesNoCopy(), &state, sizeof(DS4InputState));

    return kIOReturnSuccess;
}

static kern_return_t sGetBatteryState(OSObject * target, void * reference,
                                        IOUserClientMethodArguments * arguments)
{
    // Return battery state as 4 scalar outputs: level, cable, headphones, mic
    if (arguments->scalarOutputCount < 4) {
        return kIOReturnBadArgument;
    }

    // TODO: Read from DS4HIDDevice's current state
    arguments->scalarOutput[0] = 0;      // battery level
    arguments->scalarOutput[1] = 0;      // cable connected
    arguments->scalarOutput[2] = 0;      // headphones
    arguments->scalarOutput[3] = 0;      // microphone

    return kIOReturnSuccess;
}

// MARK: - Dispatch Table

static const IOUserClientMethodDispatch sDS4Methods[kDS4SelectorCount] = {
    // Selector 0: setLightBar(r, g, b)
    [kDS4SelectorSetLightBar] = {
        .function = sSetLightBar,
        .checkCompletionExists = false,
        .checkScalarInputCount  = 3,
        .checkStructureInputSize = 0,
        .checkScalarOutputCount = 0,
        .checkStructureOutputSize = 0,
    },
    // Selector 1: setRumble(heavy, light)
    [kDS4SelectorSetRumble] = {
        .function = sSetRumble,
        .checkCompletionExists = false,
        .checkScalarInputCount  = 2,
        .checkStructureInputSize = 0,
        .checkScalarOutputCount = 0,
        .checkStructureOutputSize = 0,
    },
    // Selector 2: getInputState()
    [kDS4SelectorGetInputState] = {
        .function = sGetInputState,
        .checkCompletionExists = false,
        .checkScalarInputCount  = 0,
        .checkStructureInputSize = 0,
        .checkScalarOutputCount = 0,
        .checkStructureOutputSize = sizeof(DS4InputState),
    },
    // Selector 3: getBatteryState()
    [kDS4SelectorGetBatteryState] = {
        .function = sGetBatteryState,
        .checkCompletionExists = false,
        .checkScalarInputCount  = 0,
        .checkStructureInputSize = 0,
        .checkScalarOutputCount = 4,
        .checkStructureOutputSize = 0,
    },
};

// MARK: - Lifecycle

bool DS4UserClient::init()
{
    if (!super::init()) {
        return false;
    }

    ivars = IONewZero(DS4UserClient_IVars, 1);
    if (!ivars) {
        return false;
    }

    os_log(OS_LOG_DEFAULT, LOG_PREFIX "init");
    return true;
}

kern_return_t DS4UserClient::Start(IOService * provider)
{
    kern_return_t ret = super::Start(provider);
    if (ret != kIOReturnSuccess) {
        return ret;
    }

    // The provider should be our DS4HIDDevice
    ivars->device = OSDynamicCast(DS4HIDDevice, provider);
    if (!ivars->device) {
        os_log(OS_LOG_DEFAULT, LOG_PREFIX "provider is not DS4HIDDevice");
        return kIOReturnBadArgument;
    }
    ivars->device->retain();

    os_log(OS_LOG_DEFAULT, LOG_PREFIX "UserClient started");
    return kIOReturnSuccess;
}

kern_return_t DS4UserClient::Stop(IOService * provider)
{
    os_log(OS_LOG_DEFAULT, LOG_PREFIX "UserClient stopping");
    OSSafeReleaseNULL(ivars->device);
    return super::Stop(provider);
}

void DS4UserClient::free()
{
    IOSafeDeleteNULL(ivars, DS4UserClient_IVars, 1);
    super::free();
}

// MARK: - External Method Dispatch

kern_return_t DS4UserClient::ExternalMethod(uint64_t selector,
                                              IOUserClientMethodArguments * arguments,
                                              const IOUserClientMethodDispatch * dispatch,
                                              OSObject * target,
                                              void * reference)
{
    if (selector >= kDS4SelectorCount) {
        os_log(OS_LOG_DEFAULT, LOG_PREFIX "Invalid selector: %llu", selector);
        return kIOReturnBadArgument;
    }

    // Use our dispatch table
    return super::ExternalMethod(selector, arguments,
                                  &sDS4Methods[selector],
                                  this, nullptr);
}
