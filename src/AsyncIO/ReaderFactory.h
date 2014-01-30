/*
 * ReaderFactory.h
 *
 *  Created on: Aug 5, 2013
 *      Author: dinal
 */

#ifndef READERFACTORY_H_
#define READERFACTORY_H_

#include <string>
#include "AbstractReader.h"
#include "AIOHandler.h"
#include "AsyncReaderManager.h"
#include <UdaUtil.h>

class ReaderFactory {
public:

	static AbstractReader* createReader(std::string type, AbstractReader::Subscriber* subscriber)
	{
		if(type.compare("blocked") == 0)
		{
			return (new AsyncReaderManager(subscriber));
		}
/*
		else if(type.compare("aio") == 0)
		{
			return (new AIOHandler(subscriber));
		}
//*/
		else
		{
			throw new UdaException("unsupported read mode");
		}
	}
};

#endif /* READERFACTORY_H_ */
