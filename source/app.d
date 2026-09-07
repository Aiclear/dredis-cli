import std.stdio;

import redis_client;
import redis_type;

void main() {
    auto redisClient = RedisClient.connect("127.0.0.1", 6379);
    scope (exit) {
        redisClient.close();
    }
    redisClient.printServerInfo();

    auto result = redisClient.execCmd("SET mykey myvalue");
    writeln("SET command result: ", result);

    auto v = redisClient.execCmd("GET mykey");
    writeln("GET command result: ", v);

    auto notExist = redisClient.execCmd("GET notexist");
    writeln("GET notexist command result: ", notExist);

    result = redisClient.execCmd("set name 余昕哲");
    writeln("SET command result: ", result);

    auto name = redisClient.execCmd("get name");
    writeln("GET command result: ", name);

    redisClient.execCmd("hset person name yuxinzhe");
    auto personName = redisClient.execCmd("hget person name");
    writeln("GET command person name: ", personName);

    redisClient.execCmd("set age 20");
    auto age = redisClient.execCmd("get age");
    writeln("GET command result: ", age);
}
