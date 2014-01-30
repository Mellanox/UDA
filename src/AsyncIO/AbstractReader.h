#ifndef ABSTRACTREADER_H_
#define ABSTRACTREADER_H_

#include <sys/types.h>
#include <string>
#include <stdint.h>
class ReadRequest;
class ReadCallbackArg;

//------------------------------------------------------------------------------
class AbstractReader
{
public:

	//-------------------------------
	class Subscriber
	{
	public:
		virtual ~Subscriber() {};
		virtual int hasFreeBuffer() = 0;
		virtual ReadCallbackArg* prepareRead(ReadRequest* req , bool shouldUseOsCache) = 0;
		virtual int readCallback(ReadCallbackArg* data, int status) = 0;
	};
	//-------------------------------


	static          AbstractReader* create(std::string type, Subscriber* subscriber); // factory method
	virtual 		~AbstractReader() {};
	virtual int 	start() = 0;
	virtual void 	insert(ReadRequest* req) = 0;
	virtual int 	submit() = 0;
	virtual void 	stop() = 0;
};


//------------------------------------------------------------------------------
class ReadRequest
{
public:

	// this CTOR expects to get buff and fd later (a la "lazy evaluation") using call to subscriber->prepareRead
	ReadRequest(const std::string & _path, int64_t _offset, int64_t _length, void *_opaque = NULL) :
		path(_path), fd (0), offset(_offset), length(_length), buff(NULL), opaque(_opaque) {}

	// this CTOR is for the case that buff or fd are already known
	ReadRequest(const std::string & _path, int64_t _offset, int64_t _length, int _fd, void *_buff = NULL, void *_opaque = NULL) :
		path(_path), fd (_fd), offset(_offset), length(_length), buff(_buff), opaque(_opaque) {}

public: // use const for public data members and avoid getters/setters

    const std::string path;		  // path to file this is only for telling us the right disk --- TODO: consider ref &
	const int         fd;         // in case fd is 0 => we'll need to use 'prepareRead'
    const int64_t     offset;     // Offset in the file
    const int64_t     length;     // needed length for reading
    void * const      buff;       // in case buff is NULL => we'll need to use 'prepareRead'
	void * const      opaque;
};

//------------------------------------------------------------------------------
class ReadCallbackArg
{
public: // use const for public data members and avoid getters/setters

	ReadCallbackArg (int _fd, void * _buff, void * _opaque) : fd(_fd), buff(_buff), opaque(_opaque) {}
	ReadCallbackArg (const ReadRequest *req) : fd(req->fd), buff(req->buff), opaque(req->opaque) {}

	const int    fd;
	void * const buff;
	void * const opaque;
};

#endif /* ABSTRACTREADER_H_ */
