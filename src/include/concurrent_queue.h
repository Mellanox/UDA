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
#ifndef __UDA_concurrent_queue_H__
#define __UDA_concurrent_queue_H__

/**
 * this file contain 3 classes that can handle concurrent_queue(s):
 *
 * * class concurrent_queue - A simple thread-safe multiple producer, multiple consumer queue
 *
 * * class concurrent_quota_queue - A thread-safe multiple producer, multiple consumer queue that is limited by quota
 *
 * * class concurrent_external_quota_queue - A thread-safe multiple producer, multiple consumer
 * queue that is limited by "external" quota and maintain the quota based on reserve/dereserve
 * operations (even before/after items are pushed/popped).
 */

#include <thread>
#include <queue>
#include <condition_variable>

 
/**
 * A simple thread-safe multiple producer, multiple consumer queue
 *
 * The code is based on: http://www.justsoftwaresolutions.co.uk/threading/implementing-a-thread-safe-queue-using-condition-variables.html
 * The main additions for UDA are:
 * 1. adaptation to our version of gcc: uses classes of gnu++0x instead of classes of boost and appropriate usage of these classes
 * 2. next classes concurrent_quota_queue and concurrent_external_quota_queue - see below
 *
 * NOTE: this code requires -std=gnu++0x compilation flag
 */
template<typename Data>
class concurrent_queue
{
private:
    std::queue<Data> m_queue;
    mutable std::mutex m_mutex;
    std::condition_variable m_condition_variable;
public:

    /** push data to our concurrent_queue */
    void push(Data const& data)
    {
    	std::unique_lock<std::mutex> lock(m_mutex);
        m_queue.push(data);
        lock.unlock();
        m_condition_variable.notify_one(); // notify that push was done and pop is allowed
    }

    /** test if queue is empty */
    bool empty() const
    {
    	std::lock_guard<std::mutex> lock(m_mutex);
        return m_queue.empty();
    }

    /** pop without blocking - returns false iff queue is empty */
    bool try_pop(Data& popped_value)
    {
    	std::lock_guard<std::mutex> lock(m_mutex);
        if(m_queue.empty())
        {
            return false;
        }

        popped_value=m_queue.front();
        m_queue.pop();
    }

    /** pop that might block in case the queue is currently empty */
    void wait_and_pop(Data& popped_value)
    {
    	std::unique_lock<std::mutex> lock(m_mutex);
        while(m_queue.empty())
        {
            m_condition_variable.wait(lock);
        }

        popped_value=m_queue.front();
        m_queue.pop();
    }
};


/**
 * A thread-safe multiple producer, multiple consumer queue that is limited by quota
 *
 * The code is based on above concurrent_queue class with few important changes:
 *   - CTOR accepts max_size argument
 *   - change: push -> wait_and_push and respect max_size
 *   - pop methods notify that push is allowed
 *   (still the class use same condition/mutex for both push and pop operations since only one can block at a time)
 *
 * NOTE: this code requires -std=gnu++0x compilation flag
 * This class was written because of hybrid merge needs
 */


template<typename Data>
class concurrent_quota_queue
{
private:
    std::queue<Data> m_queue;
    mutable std::mutex m_mutex;
    std::condition_variable m_condition_variable;
    const size_t m_quota;

public:
    concurrent_quota_queue(size_t quota) : m_quota(quota){}

    /** push data to our concurrent_queue and block if the queue already has 'm_quota' items */
    void wait_and_push(Data const& data)
    {
        std::unique_lock<std::mutex> lock(m_mutex);
        while(m_queue.size() >= m_quota) // TODO verify that m_queue.size() is O(1)
        {
            m_condition_variable.wait(lock);
        }
        m_queue.push(data);
        lock.unlock();
        m_condition_variable.notify_one(); // notify that push was done and pop is allowed
    }

    /** test if queue is empty */
    bool empty() const
    {
    	std::lock_guard<std::mutex> lock(m_mutex);
        return m_queue.empty();
    }

    /** pop without blocking - returns false iff queue is empty */
    bool try_pop(Data& popped_value)
    {
    	std::unique_lock<std::mutex> lock(m_mutex);
        if(m_queue.empty())
        {
            return false;
        }
        popped_value=m_queue.front();
        m_queue.pop();

        lock.unlock();
        m_condition_variable.notify_one(); // notify that pop was done and push is allowed
        return true;
    }

    /** pop that might block in case the queue is currently empty */
    void wait_and_pop(Data& popped_value)
    {
    	std::unique_lock<std::mutex> lock(m_mutex);
        while(m_queue.empty())
        {
            m_condition_variable.wait(lock);
        }
        popped_value=m_queue.front();
        m_queue.pop();

        lock.unlock();
        m_condition_variable.notify_one(); // notify that pop was done and push is allowed
    }
};

/**
 * A thread-safe multiple producer, multiple consumer queue that is limited by "external" quota
 * and maintain the quota based on reserve/dereserve operations (even before/after items are
 * pushed/popped).
 *
 * This class is based on above concurrent_quota queue class with a big difference.
 * Here the queue allows items to be outside the queue and still considering them as part of its quota.
 * This affect the quota in 2 places:
 *   * items can be 'reserved' on the queue's quota even before they are pushed to   the queue
 *   * items can be considered on the queue's quota even  after they are popped from the queue
 * This semantic changes EVERYTHING in the queue
 *
 * NOTE: this code requires -std=gnu++0x compilation flag
 * This class was written because of hybrid merge needs
 */

template<typename Data>
class concurrent_external_quota_queue
{
private:
    std::queue<Data> m_queue;
    mutable std::mutex m_mutex;
    std::condition_variable m_cv_push_allowed;
    std::condition_variable m_cv_pop_allowed;
    const size_t m_quota;
    size_t m_in_use; // in use from quota

public:
    concurrent_external_quota_queue(size_t quota) : m_quota(quota), m_in_use(0){}

    /** block until we are allowed to produce 1 more item */
    void wait_and_reserve()
    {
        std::unique_lock<std::mutex> lock(m_mutex);
        while(m_in_use >= m_quota)
        {
        	m_cv_push_allowed.wait(lock);
        }
        ++m_in_use;
    }

    /** push data to our queue "into" quota that was already reserved. This goes without blocking. */
    void push_reserved(Data const& data)
    {
        std::unique_lock<std::mutex> lock(m_mutex);
        m_queue.push(data);
        lock.unlock();
        m_cv_pop_allowed.notify_one(); // notify that reserve&push completed and pop&dereserved allowed
    }

    /** test if queue is empty */
    bool empty() const
    {
    	std::lock_guard<std::mutex> lock(m_mutex);
        return m_queue.empty();
    }

    /** pop without blocking - returns false iff queue is empty.  Data is still considered on the queue's quota */
    bool try_pop_without_dereserve(Data& popped_value)
    {
    	std::unique_lock<std::mutex> lock(m_mutex);
        if(m_queue.empty())
        {
            return false;
        }
        popped_value=m_queue.front();
        m_queue.pop();
        // no notify until Data is dereserved
        return true;
    }

    /** pop that might block in case the queue is currently empty.  Data is still considered on the queue's quota */
    void wait_and_pop_without_dereserve(Data& popped_value)
    {
    	std::unique_lock<std::mutex> lock(m_mutex);
        while(m_queue.empty())
        {
        	m_cv_pop_allowed.wait(lock);
        }
        popped_value=m_queue.front();
        m_queue.pop();
        // no notify until Data is dereserved
    }

    /** dereserve quota that we popped and consumed */
    void dereserve()
    {
      std::unique_lock<std::mutex> lock(m_mutex);
      --m_in_use;
      lock.unlock();
      m_cv_push_allowed.notify_one(); // notify that pop&dereserve completed and reserve&push is possible
    }
};

#endif /// ! __UDA_concurrent_queue_H__
/*
 * Local variables:
 *  c-indent-level: 4
 *  c-basic-offset: 4
 * End:
 *
 * vim: ts=4 sw=4 hlsearch cindent expandtab 
 */
