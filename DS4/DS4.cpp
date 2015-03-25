#include <IOKit/IOLib.h>
#include <IOKit/usb/IOUSBDevice.h>
#include <IOKit/usb/IOUSBInterface.h>

namespace HID_DS4 {
	#include "dualshock4hid.h"
}

#include "DS4.h"

// This required macro defines the class's constructors, destructors,
// and several other methods I/O Kit requires.
OSDefineMetaClassAndStructors(SonyPlaystationDualShock4, IOHIDDevice)

// Define the driver's superclass.
#define super IOHIDDevice

bool SonyPlaystationDualShock4::init(OSDictionary *dict)
{
	bool result = super::init(dict);
	
	IOLog("DS4 Initializing\n");
	
	return result;
}

void SonyPlaystationDualShock4::free(void)
{
	IOLog("DS4 Freeing\n");
	super::free();
}

IOService *SonyPlaystationDualShock4::probe(IOService *provider,
												SInt32 *score)
{
	IOService *result = IOHIDDevice::probe(provider, score);
	IOLog("DS4 Probing\n");
	return result;
}

bool SonyPlaystationDualShock4::start(IOService *provider)
{
	bool result = IOHIDDevice::start(provider);
	IOLog("DS4 Starting\n");
	return result;
}

void SonyPlaystationDualShock4::stop(IOService *provider)
{
	IOLog("DS4 Stopping\n");
	super::stop(provider);
}

IOReturn SonyPlaystationDualShock4::newReportDescriptor(IOMemoryDescriptor **descriptor) const
{
	IOLog("DS4 In report descriptor\n");
	IOBufferMemoryDescriptor *buffer = IOBufferMemoryDescriptor::inTaskWithOptions(
																				   kernel_task,
																				   0,
																				   sizeof(HID_DS4::ReportDescriptor)
																				   );
	
	if (buffer == NULL)
		return kIOReturnNoResources;
	
	buffer->writeBytes(0, HID_DS4::ReportDescriptor,sizeof(HID_DS4::ReportDescriptor));
	
	*descriptor = buffer;
	
	return kIOReturnSuccess;
}