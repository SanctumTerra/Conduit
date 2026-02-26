#ifndef STORAGE_LEVELDB_PORT_PORT_CONFIG_H_
#define STORAGE_LEVELDB_PORT_PORT_CONFIG_H_

#if !defined(HAVE_FDATASYNC)
#define HAVE_FDATASYNC 0
#endif

#if !defined(HAVE_FULLFSYNC)
#define HAVE_FULLFSYNC 0
#endif

#if !defined(HAVE_O_CLOEXEC)
#define HAVE_O_CLOEXEC 0
#endif

#if !defined(HAVE_CRC32C)
#define HAVE_CRC32C 0
#endif

#if !defined(HAVE_SNAPPY)
#define HAVE_SNAPPY 0
#endif

#if !defined(HAVE_ZSTD)
#define HAVE_ZSTD 0
#endif

#endif
