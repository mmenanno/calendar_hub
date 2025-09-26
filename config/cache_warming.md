# Cache Warming Configuration

## Overview

The Calendar Hub application includes intelligent cache warming to improve search
performance, especially when using title mappings. Cache warming pre-loads
frequently accessed data into the cache during application startup.

## Configuration

Cache warming behavior is controlled by the `WARM_CACHE_ON_STARTUP` environment
variable:

### Production (Default: Enabled)

```bash
# Enable cache warming (default)
WARM_CACHE_ON_STARTUP=true

# Disable cache warming
WARM_CACHE_ON_STARTUP=false
```

### Development (Default: Disabled)

```bash
# Enable cache warming for development
WARM_CACHE_ON_STARTUP=true

# Disable cache warming (default)
WARM_CACHE_ON_STARTUP=false
```

### Test (Always Disabled)

Cache warming is automatically disabled in test environment to avoid interfering
with test performance and isolation.

## What Gets Cached

### 1. EventMapping Cache

- Active mappings for each calendar source
- Global mappings (not tied to specific source)
- **TTL**: 5 minutes
- **Invalidation**: Automatic when mappings change

### 2. Mapped Title Cache

- Computed mapped titles for events
- **TTL**: 1 hour
- **Invalidation**: Automatic when events update

### 3. Search Data Cache

- Pre-computed search data (lowercased titles, locations)
- **TTL**: 30 minutes
- **Invalidation**: Automatic when events update

## Performance Impact

### Startup Time

- **Cold start**: +1-2 seconds (cache warming runs in background)
- **Warm start**: No impact (cache already populated)

### Memory Usage

- **Minimal**: Only recent events (50 events) are cached
- **Efficient**: Uses Rails' built-in cache size limits

### Search Performance

- **First search**: Slightly slower (populates remaining cache)
- **Subsequent searches**: 2-5x faster depending on data size

## Manual Cache Management

### Warm Cache Manually

```bash
bin/rails cache:warm
```

### Clear Search Caches

```bash
bin/rails cache:clear_search
```

## Deployment Recommendations

### Production

- **Enable cache warming** for best user experience
- Consider warming cache after deployments
- Monitor memory usage if you have many events

### Development

- **Disable by default** for faster startup during development
- **Enable occasionally** to test cache behavior
- Use `bin/rails cache:warm` when needed

### Docker/Container Deployments

Cache warming works well with container deployments since it runs in the
background and doesn't block the health check endpoint.

## Monitoring

Cache warming logs are written to the Rails logger:

```text
[CacheWarmer] Starting cache warming...
[CacheWarmer] Name mapper caches warmed
[CacheWarmer] Event search caches warmed for 42 events
[CacheWarmer] Cache warming completed successfully
```

Failed cache warming (non-critical):

```text
[CacheWarmer] Cache warming failed: Database connection error
```

## Troubleshooting

### Cache Not Working

1. Check that Solid Cache is properly configured
2. Verify database connectivity during startup
3. Check Rails logs for cache warming messages

### High Memory Usage

1. Reduce cache TTL values in the initializer
2. Limit the number of events cached (currently 50)
3. Monitor with `bin/rails cache:clear_search`

### Slow Startup

1. Disable cache warming: `WARM_CACHE_ON_STARTUP=false`
2. Use manual warming after startup: `bin/rails cache:warm`
