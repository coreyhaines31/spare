#ifndef CSPARE_H
#define CSPARE_H
#include <stdint.h>
#include <stdbool.h>
typedef struct {
    int pid, parent_pid;
    uint32_t uid;
    uint64_t started, cpu_ns, memory;
    char name[256], path[4096], directory[4096];
} SpareProcess;
typedef struct {
    uint32_t cpu[4];
    uint64_t physical, used, compressed, swap;
    int pressure;
} SpareSystem;
int spare_pids(int *pids, int capacity);
bool spare_process(int pid, SpareProcess *output, bool details);
bool spare_system(SpareSystem *output);
int spare_ports(int pid, uint16_t *ports, int capacity);
bool spare_matches(int pid, uint64_t started);
int spare_stop(int pid, uint64_t started);
#endif
