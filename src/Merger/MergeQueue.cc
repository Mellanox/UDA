/*
** Copyright (C) 2012 Auburn University
** Copyright (C) 2012 Mellanox Technologies
** 
** Licensed under the Apache License, Version 2.0 (the "License");
** you may not use this file except in compliance with the License.
** You may obtain a copy of the License at:
**  
** http://www.apache.org/licenses/LICENSE-2.0
** 
** Unless required by applicable law or agreed to in writing, software
** distributed under the License is distributed on an "AS IS" BASIS,
** WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, 
** either express or implied. See the License for the specific language 
** governing permissions and  limitations under the License.
**
**
*/

#include "MergeQueue.h"
#include "reducer.h"

using namespace std;

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

/*
 * Local variables:
 *  c-indent-level: 4
 *  c-basic-offset: 4
 * End:
 *
 * vim: ts=4 sw=4 hlsearch cindent expandtab 
 */
