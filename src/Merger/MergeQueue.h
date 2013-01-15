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

#ifndef PRIORITYQUEUE_H_
#define PRIORITYQUEUE_H_

#define NUM_STAGE_MEM (2)


#include <vector>
#include <list>
#include <string>

#include <LinkList.h>
#include <NetlevComm.h>

#include "IOUtility.h"

class RawKeyValueIterator;

typedef struct mem_desc {
    struct list_head     list;
    char                *buff;
    int32_t              buf_len;
    int32_t              act_len;
    volatile int         status; /* available or invalid*/
    struct memory_pool  *owner;  /* owner pool */
    pthread_mutex_t      lock;
    pthread_cond_t       cond;

} mem_desc_t;


//#include "StreamRW.h"
//#include "MergeManager.h"

/****************************************************************************
 * A PriorityQueue maintains a partial ordering of its elements such that the
 * least element can always be found in constant time.  Put()'s and pop()'s
 * require log(size) time. 
 ****************************************************************************/
template <class T>
class PriorityQueue
{
private:
    std::vector<T> m_heap;
    int            m_size;
    int            m_maxSize;

public:

    PriorityQueue<T>(int maxSize) {
        m_size = 0;
        int heapSize = maxSize + 1;
        m_maxSize = maxSize;
        m_heap.resize(heapSize);
        for (int i = 0; i < heapSize; ++i) {
            m_heap[i] = NULL;
        }
    }
    
    virtual ~PriorityQueue() {}
  
    /**
     * Right now, there is no extra exception handling in thi part
     * Please avoid putting too mand objects into the priority queue
     * so that the total number exceeds the maxSize
     */
    void put(T element) {
        m_size++;
        m_heap[m_size] = element;
        upHeap();
    }

#if 0
    /**
     * Adds element to the PriorityQueue in log(size) time if either
     * the PriorityQueue is not full, or not lessThan(element, top()).
     * @param element
     * @return true if element is added, false otherwise.
     */
    bool insert(T element) {
        if (m_size < m_maxSize) {
            put(element);
            return true;
        }
        else if (m_size > 0 && !(*element < *(top()))) {
            m_heap[1] = element;
            adjustTop();
            return true;
        }
        else {
            return false;
        }
    }
#endif

    /** 
     * Returns the least element of the PriorityQueue in constant time. 
     */
    T top() {
        if (m_size > 0)
            return m_heap[1];
        else
            return NULL;
    }

    /**
     * (1) Pop the element on the top of the priority queue, which should be
     *     the least among current objects in queue.
     * (2) Move the last object in the queue to the first place
     * (3) Call downHeap() to find the least object and put it on the first
     *     position.
     */
    T pop() {
        if (m_size > 0) {
            T result = m_heap[1];      /* save first value*/
            m_heap[1] = m_heap[m_size];/* move last to first*/
            m_heap[m_size] = NULL;	   /* permit GC of objects*/
            m_size--;
            downHeap();		 /* adjust heap*/
            return result;
        } else {
            return NULL;
        }
    }

    /* Be called when the object at top changes values.*/
    void adjustTop() {
        downHeap();
    }

    /*get the total number of objects stording in priority queue.*/
    int size() { 
        return m_size; 
    }

    /*reset the priority queue*/
    void clear() {
        for (int i = 0; i <= m_size; i++)
            m_heap[i] = NULL;
        m_size = 0;
    }

private:
    
    void upHeap() {
        int i = m_size;
        T node = m_heap[i];			  /* save bottom node*/
        int j = i >> 1;
        while (j > 0 && (*node < *(m_heap[j]))) {
            m_heap[i] = m_heap[j];	  /* shift parents down*/
            i = j;
            j = j >> 1;				 
        }
        m_heap[i] = node;			  /* install saved node*/
    }

    void downHeap() {
        int i = 1;
        T node = m_heap[i];			  /* save top node*/
        int j = i << 1;				  /* find smaller child*/
        int k = j + 1;
        if (k <= m_size && (*(m_heap[k]) < *(m_heap[j]))) {
            j = k;
        }

        while (j <= m_size && (*(m_heap[j]) < *node)) {
            m_heap[i] = m_heap[j];	  /* shift up child*/
            i = j;
            j = i << 1;
            k = j + 1;
            if (k <= m_size && (*(m_heap[k]) < *m_heap[j])) {
                j = k;
            }
        }
        m_heap[i] = node;			  /* install saved node*/
    }
};


/****************************************************************************
 * The implementation of PriorityQueue and RawKeyValueIterator
 ****************************************************************************/
template <class T>
class MergeQueue 
{
private:
    std::list<T> *mSegments;
    T min_segment;
    DataStream *key;
    DataStream *val;
    int num_of_segments;
public:
    const std::string filename;
    mem_desc_t*  staging_bufs[NUM_STAGE_MEM];
    PriorityQueue<T> core_queue;
public: 
	#if LCOV_HYBRID_MERGE_DEAD_CODE
    	size_t getQueueSize() { return num_of_segments; }
	#endif

    virtual ~MergeQueue(){}
    int        mergeq_flag;  /* flag to check the former k,v */
    RawKeyValueIterator* merge(int factor, int inMem, std::string &tmpDir);
    DataStream* getKey() { return this->key; }
    DataStream* getVal() { return this->val; }
    bool next() {
        if(this->mergeq_flag) {
            return true;
        }

        if (core_queue.size() == 0) {
        	return false;
        }


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

    bool insert(T segment){
        int ret = segment->nextKV();
        switch (ret) {
            case 0: { /*end of the map output*/
                delete segment;
                break;
            }
            case 1: { /*next keyVal exist*/
                core_queue.put(segment);
                num_of_segments++;
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

        return true;
    }

    int32_t get_key_len() {return this->min_segment->cur_key_len;}
    int32_t get_val_len() {return this->min_segment->cur_val_len;}
    int32_t get_key_bytes(){return this->min_segment->kbytes;}
    int32_t get_val_bytes() {return this->min_segment->vbytes;}

      MergeQueue(int numMaps, mem_desc_t* staging_descs = NULL ,const char*fname = "") : filename(fname), core_queue(numMaps)
{
    	this->num_of_segments=0;
        this->mSegments = NULL;
        this->min_segment = NULL;
        this->key = NULL;
        this->val = NULL;
        this->mergeq_flag = 0;
         
        if (staging_descs) {
        	for (int i=0;i < NUM_STAGE_MEM; i++)  
		        this->staging_bufs[i] = &staging_descs[i];
        }
		else{
        	for (int i=0;i < NUM_STAGE_MEM; i++)  
		        this->staging_bufs[i] = NULL;
		}
        
        core_queue.clear();
        
    }

#if 0
		MergeQueue(std::list<T> *segments){
			this->mSegments = segments;
			this->min_segment = NULL;
		}
#endif



protected:

    bool lessThan(T a, T b);
    void adjustPriorityQueue(T segment){
        int ret = segment->nextKV();

        switch (ret) {
            case 0: { /*no more data for this segment*/
                T s = core_queue.pop();
                delete s;
                num_of_segments--;
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
                    T s = core_queue.pop();
                    num_of_segments--;
                    delete s;
                }
                break;
            }
        }
    }


    int  getPassFactor(int factor, int passNo, int numSegments);
    void getSegmentDescriptors(std::list<T> &inputs,
                               std::list<T> &outputs,
                               int numDescriptors);

};

#endif

/*
 * Local variables:
 *  c-indent-level: 4
 *  c-basic-offset: 4
 * End:
 *
 * vim: ts=4 sw=4 hlsearch cindent expandtab 
 */
