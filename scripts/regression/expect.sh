#!/usr/bin/expect 

# Written by Elad Itzhakian 09.10.13
# If your script doesn't require arguments use "" instead


if {$argc != 3} {
    puts "Usage: $argv0 <script path> <script argument> <password>"
    exit 1
}

set script [lindex $argv 0]
set arg [lindex $argv 1]
set pass [lindex $argv 2]

spawn bash $script $arg

while {1} {
  expect {
    eof                          {break}
    "The authenticity of host"   {send "yes\r"}
    "password:"                  {send "$pass\r"}
    "*\]"                        {send "exit\r"}
  }
}
wait
