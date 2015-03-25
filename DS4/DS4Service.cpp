//
//  DS4Service.cpp
//  DS4
//
//  Created by Kevin Hallmark on 3/24/15.
//  Copyright (c) 2015 Little Black Hat. All rights reserved.
//


#include <IOKit/IOLib.h>
#include "DS4Service.h"

// This required macro defines the class's constructors, destructors,
// and several other methods I/O Kit requires.
OSDefineMetaClassAndStructors(DS4Service, IOService)

// Define the driver's superclass.
#define super IOService

bool DS4Service::init(OSDictionary *dict)
{
	bool result = super::init(dict);
	IOLog("Service Initializing\n");
	return result;
}

void DS4Service::free(void)
{
	IOLog("Service Freeing\n");
	super::free();
}

IOService *DS4Service::probe(IOService *provider,
												SInt32 *score)
{
	IOService *result = super::probe(provider, score);
	IOLog("Service Probing\n");
	return result;
}

bool DS4Service::start(IOService *provider)
{
	bool result = super::start(provider);
	IOLog("Service Starting\n");
	return result;
}

void DS4Service::stop(IOService *provider)
{
	IOLog("Service Stopping\n");
	super::stop(provider);
}
