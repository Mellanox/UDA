/*
 * AbstractReader.cc
 *
 *  Created on: Aug 7, 2013
 *      Author: dinal
 */

using namespace std;
#include <string>
#include "AbstractReader.h"
#include "ReaderFactory.h"


AbstractReader* AbstractReader::create(string type, AbstractReader::Subscriber* subscriber)
{
	return ReaderFactory::createReader(type, subscriber);
}



