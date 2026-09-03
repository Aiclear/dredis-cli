import redis_client;

void main() {
    auto redisClient = RedisClient.connect("127.0.0.1", 6379);
    scope (exit) {
        redisClient.close();
    }
    redisClient.printServerInfo();
}
