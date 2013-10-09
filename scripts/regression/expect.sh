#!/usr/bin/expect 

set script [lindex $argv 0]
set pass [lindex $argv 1]

spawn bash $script

while {1} {
  expect {
 
    eof                          {break}
    "The authenticity of host"   {send "yes\r"}
    "password:"                  {send "$pass\r"}
    "*\]"                        {send "exit\r"}
  }
}
wait
