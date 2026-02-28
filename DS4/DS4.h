#include <IOKit/hid/IOHIDDevice.h>

class SonyPlaystationDualShock4 : public IOHIDDevice
{
	OSDeclareDefaultStructors(SonyPlaystationDualShock4)
	
public:
	virtual bool init(OSDictionary *dictionary = 0) override;
	virtual void free(void) override;
	virtual IOService *probe(IOService *provider, SInt32 *score) override;
	virtual bool start(IOService *provider) override;
	virtual void stop(IOService *provider) override;
	
	
	
	virtual IOReturn newReportDescriptor(IOMemoryDescriptor **descriptor) const override;
};

