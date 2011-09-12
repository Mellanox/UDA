/*
** Copyright (C) Mellanox Technologies Ltd. 2001-2011.  ALL RIGHTS RESERVED.
**
** This software product is a proprietary product of Mellanox Technologies Ltd.
** (the "Company") and all right, title, and interest in and to the software product,
** including all associated intellectual property rights, are and shall
** remain exclusively with the Company.
**
** This software product is governed by the End User License Agreement
** provided with the software product.
**
*/

using namespace std;

#include "reducer.h"
#include "MergeQueue.h"

MergeQueue::MergeQueue(std::list<Segment*> *segments) 
{
    this->mSegments = segments;    
    this->min_segment = NULL;
}


MergeQueue::MergeQueue(int numMaps) 
{
    this->mSegments = NULL;
    this->min_segment = NULL;
    this->key = NULL;
    this->val = NULL;
    this->mergeq_flag = 0;
    this->staging_bufs[0] = NULL;
    this->staging_bufs[1] = NULL;
    core_queue.initialize(numMaps);
    core_queue.clear();
}

MergeQueue::~MergeQueue()
{
}


bool MergeQueue::insert(Segment *segment) 
{
    int ret = segment->nextKV();
    switch (ret) {
        case 0: { /*end of the map output*/
            delete segment;
            break;
        }
        case 1: { /*next keyVal exist*/
            core_queue.put(segment);
            break;
        }
        case -1: { /*break in the middle of the data*/
            output_stderr("MergeQueue:break in the first KV pair");
            segment->switch_mem();
            break;
        }
        default:
            output_stderr("MergeQueue: Error in insert");
            break;
    }

    write_log(segment->map_output->task->reduce_log, 
              DBG_CLIENT, "MergeQueue: current size %d", 
              core_queue.size());

    return true;
}

#if 0
int MergeQueue::getPassFactor(int factor, int passNo, int numSegments) 
{
    if (passNo > 1 || numSegments <= factor || factor == 1) 
        return factor;
    int mod = (numSegments - 1) % (factor - 1);
    if (mod == 0)
        return factor;
    return mod + 1;
}

void MergeQueue::getSegmentDescriptors(std::list<Segment*> &inputs, 
                                       std::list<Segment*> &outputs,
                                       int numDescriptors)
{
    int count = 0;
    while (inputs.size() > 0 && count <= numDescriptors) {
        outputs.push_back(inputs.front());
        inputs.pop_front();
        ++count;
    } 
}

RawKeyValueIterator*
MergeQueue::merge(int factor, int inMem, std::string &tmpDir)
{
    int numSegments = this->mSegments->size();
    int origFactor = factor;
    int passNo = 1;

    do {
        factor = getPassFactor(factor, passNo, numSegments - inMem);
        printf("MergeQueue:merge, factor(%d) passNo(%d)\n", factor, passNo);
        if (1 == passNo) {
            factor += inMem;
        } 
        std::list<Segment*> segmentsToMerge;
        int segmentsConsidered = 0;
        int numSegmentsToConsider = factor;
        while (true) {
            std::list<Segment*> mStream;
            getSegmentDescriptors(*this->mSegments, mStream,
                                  numSegmentsToConsider);
            printf("MergeQueue:merge: mStream size %d\n", mStream.size());
            std::list<Segment*>::iterator iter = mStream.begin();
            while (iter != mStream.end()) {
                Segment *segment = *iter;
                iter++;
                int hasNext = segment->nextKV();
                printf("MergeQueue:merge: hasNext %d\n", hasNext);
                if (hasNext == 1) {
                    printf("MergeQueue:TEST 1\n");
                    segmentsToMerge.push_back(segment);
                    segmentsConsidered++;
                } else {
                    printf("MergeQueue:TEST 2\n");
                    delete segment;
                    numSegments--;
                }
            }
            printf("MergeQueue:segmentsConsidered(%d), mSegments size(%d)\n",
                   segmentsConsidered, mSegments->size());

            if (segmentsConsidered == factor || 
                this->mSegments->size() == 0) {
                break;
            }
            numSegmentsToConsider = factor - segmentsConsidered;
        }
        initialize(segmentsToMerge.size());  
        clear(); 
        std::list<Segment*>::iterator iter=segmentsToMerge.begin();
        int64_t mergedBytes = 0;
        while (iter != segmentsToMerge.end()) {
            mergedBytes += (*iter)->getLength();
            put(*iter);
            ++iter;
        } 

        if (numSegments <= factor) {
            return this;
        } else {
            char buf[500]; 
            sprintf(buf, "%sintermediate.%d", tmpDir.c_str(), passNo);
            string tmp_file_name(buf);
            write_kv_to_disk(this,buf);
            clear();
            Segment *newSegment = new Segment(tmp_file_name);
            this->mSegments->push_back(newSegment);
            numSegments = this->mSegments->size();
            passNo++;   
        }
        factor = origFactor; 
    } while (true);
}
#endif

int32_t MergeQueue::get_key_len()
{
    return this->min_segment->cur_key_len;
}

int32_t MergeQueue::get_val_len()
{
    return this->min_segment->cur_val_len;
}

int32_t MergeQueue::get_key_bytes()
{
    return this->min_segment->kbytes;
}

int32_t MergeQueue::get_val_bytes()
{
    return this->min_segment->vbytes;
}

bool MergeQueue::next()
{
    if(this->mergeq_flag)
        return true;

    if (core_queue.size() == 0) return false;
  
    if (this->min_segment != NULL) {
        this->adjustPriorityQueue(this->min_segment);
        if (core_queue.size() == 0) {
            this->min_segment = NULL;
            return false;
        }
    }
    this->min_segment = core_queue.top();
    this->key = &this->min_segment->key;
    this->val = &this->min_segment->val;
    return true; 
}


void MergeQueue::adjustPriorityQueue(Segment *segment)
{
    int ret = segment->nextKV();
    
    switch (ret) {
        case 0: { /*no mre data for this segment*/
            Segment *s = core_queue.pop();
            delete s;
            break;
        } 
        case 1: { /*next KV pair exist*/
            core_queue.adjustTop();
            break;
        }
        case -1: { /*break in the middle*/
            if (segment->switch_mem() ){
                /* DBGPRINT(DBG_CLIENT, "adjust priority queue\n"); */
                core_queue.adjustTop();
            } else {
                Segment *s = core_queue.pop();
                delete s;
            }
            break;
        }
    }
}

/*
 * Local variables:
 *  c-indent-level: 4
 *  c-basic-offset: 4
 * End:
 *
 * vim: ts=4 sw=4 hlsearch cindent expandtab 
 */
