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
}
