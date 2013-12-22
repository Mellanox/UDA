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
#ifndef __UDA_UTIL_H__
#define __UDA_UTIL_H__

#include <pthread.h>
#include <vector>
#include <list>
#include <string>

#include <IOUtility.h> // temp - for UdaException


// -----------------------------------------------------------------------------
/**
 * wrapper around pthread_create! has same interface but does additional actions
 * ALL UDA Threads must use it!
 */
#define uda_thread_create(a, b, c, d)  uda_thread_create_func(a, b, c, d, __func__)

// -----------------------------------------------------------------------------
int uda_thread_create_func (pthread_t *__restrict __newthread,
			   __const pthread_attr_t *__restrict __attr,
			   void *(*__start_routine) (void *),
			   void *__restrict __arg,
			   const char * __caller_func) throw (UdaException*) __nonnull ((1, 3));



// -----------------------------------------------------------------------------
/**
 * implement the O(n) array shuffle algorithm - known as The modern version of the Fisher–Yates shuffle.
 * To shuffle an array a of n elements (indices 0..n-1):
 *   for i from n - 1 downto 1 do
 *       j <- random integer with 0 <= j <= i
 *       exchange a[j] and a[i]
 *
 * NOTE: this function assumes srand was called in advance
 */
template <class T>
void vector_shuffle(std::vector<T> & vec) {
	size_t n = vec.size();
	if (n<2) return; // nothing to do

	for (int i = n-1; i > 0; --i) {
		int j = rand() % (i+1);
		T temp = vec[j];
		vec[j] = vec[i];
		vec[i] = temp;
	}
}

// -----------------------------------------------------------------------------
/** move all elements from 'list' to the back of vector_out under list_lock
 * (this function assumes srand was called in advance)
 *
 * TODO: I have an idea for a faster algorithm (based on the fact that the vector is already shuffled)
 */
template <class T>
void list_append_to_vector(std::vector<T> & vector_out, std::list<T> & list, pthread_mutex_t *list_lock) {
	pthread_mutex_lock(list_lock);

	size_t n = list.size();
	vector_out.reserve(vector_out.size() + n);

	for (size_t i = 0; i < n; ++i) {
		vector_out.push_back(list.front());
		list.pop_front();
	}

	pthread_mutex_unlock(list_lock);
}

// -----------------------------------------------------------------------------
/**
 * This is an O(n) list shuffle that will empty list and put the shuffled result in vector_out
 * (this function assumes srand was called in advance)
 *
 * TODO: I have an idea for a faster algorithm (based on the fact that the vector is already shuffled)
 */
template <class T>
void list_shuffle_in_vector(std::vector<T> & vector_out, std::list<T> & list, pthread_mutex_t *list_lock) {
	list_append_to_vector(vector_out, list, list_lock);
	vector_shuffle(vector_out); // no lock here
}



#endif /// ! __UDA_UTIL_H__
/*
 * Local variables:
 *  c-indent-level: 4
 *  c-basic-offset: 4
 * End:
 *
 * vim: ts=4 sw=4 hlsearch cindent expandtab 
 */
