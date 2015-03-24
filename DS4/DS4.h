#include <IOKit/usb/IOUSBDevice.h>
#include <IOKit/hid/IOHIDDevice.h>

class SonyPlaystationDualShock4 : public IOHIDDevice
{
	OSDeclareDefaultStructors(SonyPlaystationDualShock4)
	
public:
//	virtual bool init(OSDictionary *dictionary = 0);
//	virtual void free(void);
	virtual IOService *probe(IOService *provider, SInt32 *score);
	virtual bool start(IOService *provider);
//	virtual void stop(IOService *provider);
	
	
	
	virtual IOReturn newReportDescriptor(IOMemoryDescriptor **descriptor) const;
};