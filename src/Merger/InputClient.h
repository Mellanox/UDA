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

#ifndef ROCE_INPUT_CLIENT_H
#define ROCE_INPUT_CLIENT_H      1


class  RdmaClient;
struct merging_state;
struct client_part_req;



class InputClient 
{
public:

    virtual ~InputClient() = 0;

    virtual void start_client() = 0;
    virtual void stop_client() = 0;

    /* XXX: the general flow of a fetch request for a client
     * 1. prepare the request 
     * 2. post a request for partition (unknown length) with 
     *    the 1st registered segment 
     * 3. receive the first segment, along with the total length 
     * -- Done if the total length is shorter than the default area
     * -- Otherwise, continue
     * 4. find out the length of the entire partition
     * 5. post the information on the remaining data
     * 6. receive the remaining data 
     * 7. For network levitation, only use the 1st registered segment
     *    to receive more data
     */
    virtual int start_fetch_req(struct client_part_req *req, char *buff, int32_t buf_len) = 0;
    virtual void comp_fetch_req(struct client_part_req *req) = 0;
    virtual RdmaClient* getRdmaClient() = 0;


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
