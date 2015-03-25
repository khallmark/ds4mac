//
//  DS4Service.h
//  DS4
//
//  Created by Kevin Hallmark on 3/24/15.
//  Copyright (c) 2015 Little Black Hat. All rights reserved.
//

#include <IOKit/IOService.h>
class DS4Service : public IOService
{
	OSDeclareDefaultStructors(DS4Service)
public:
	virtual bool init(OSDictionary *dictionary = 0);
	virtual void free(void);
	virtual IOService *probe(IOService *provider, SInt32 *score);
	virtual bool start(IOService *provider);
	virtual void stop(IOService *provider);
};