#include "CSpare.h"
#include <libproc.h>
#include <sys/proc_info.h>
#include <sys/resource.h>
#include <sys/sysctl.h>
#include <mach/mach.h>
#include <unistd.h>
#include <signal.h>
#include <errno.h>
#include <string.h>
#include <stdlib.h>
#include <arpa/inet.h>

int spare_pids(int *pids, int capacity) {
    return proc_listpids(PROC_ALL_PIDS, 0, pids, capacity * (int)sizeof(int)) / (int)sizeof(int);
}

bool spare_process(int pid, SpareProcess *output, bool details) {
    struct proc_bsdinfo info = {0};
    if (proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, sizeof(info)) != sizeof(info)) return false;
    if (info.pbi_uid != getuid()) return false;
    memset(output, 0, sizeof(*output));
    output->pid = pid;
    output->parent_pid = info.pbi_ppid;
    output->uid = info.pbi_uid;
    output->started = info.pbi_start_tvsec * 1000000 + info.pbi_start_tvusec;
    struct rusage_info_v2 usage = {0};
    if (proc_pid_rusage(pid, RUSAGE_INFO_V2, (rusage_info_t *)&usage) != 0) return false;
    output->cpu_ns = usage.ri_user_time + usage.ri_system_time;
    output->memory = usage.ri_phys_footprint;
    proc_name(pid, output->name, sizeof(output->name));
    if (details) {
        proc_pidpath(pid, output->path, sizeof(output->path));
        struct proc_vnodepathinfo paths = {0};
        if (proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &paths, sizeof(paths)) == sizeof(paths)) {
            strlcpy(output->directory, paths.pvi_cdir.vip_path, sizeof(output->directory));
        }
    }
    return true;
}

bool spare_matches(int pid, uint64_t started) {
    SpareProcess process;
    return spare_process(pid, &process, false) && process.started == started;
}

int spare_stop(int pid, uint64_t started) {
    if (pid <= 1 || pid == getpid()) return EPERM;
    SpareProcess process;
    if (!spare_process(pid, &process, true) || process.started != started) return ESRCH;
    if (process.path[0] == '\0' || strncmp(process.path, "/System/", 8) == 0 ||
        strncmp(process.path, "/usr/libexec/", 13) == 0 ||
        strncmp(process.path, "/usr/sbin/", 10) == 0) return EPERM;
    return kill(pid, SIGTERM) == 0 ? 0 : errno;
}

bool spare_system(SpareSystem *output) {
    memset(output, 0, sizeof(*output));
    output->pressure = -1;
    size_t size = sizeof(output->pressure);
    sysctlbyname("kern.memorystatus_vm_pressure_level", &output->pressure, &size, NULL, 0);
    size = sizeof(output->physical);
    if (sysctlbyname("hw.memsize", &output->physical, &size, NULL, 0) != 0) return false;
    struct xsw_usage swap = {0};
    size = sizeof(swap);
    if (sysctlbyname("vm.swapusage", &swap, &size, NULL, 0) == 0) output->swap = swap.xsu_used;
    mach_port_t host = mach_host_self();
    host_cpu_load_info_data_t cpu;
    mach_msg_type_number_t count = HOST_CPU_LOAD_INFO_COUNT;
    bool success = host_statistics(host, HOST_CPU_LOAD_INFO, (host_info_t)&cpu, &count) == KERN_SUCCESS;
    if (success) memcpy(output->cpu, cpu.cpu_ticks, sizeof(output->cpu));
    vm_statistics64_data_t vm;
    count = HOST_VM_INFO64_COUNT;
    vm_size_t page_size;
    if (host_page_size(host, &page_size) == KERN_SUCCESS &&
        host_statistics64(host, HOST_VM_INFO64, (host_info64_t)&vm, &count) == KERN_SUCCESS) {
        output->compressed = (uint64_t)vm.compressor_page_count * page_size;
        uint64_t occupied = (uint64_t)vm.active_count + vm.inactive_count + vm.wire_count +
            vm.speculative_count + vm.compressor_page_count;
        uint64_t reusable = (uint64_t)vm.external_page_count + vm.purgeable_count;
        output->used = (occupied > reusable ? occupied - reusable : 0) * page_size;
    }
    mach_port_deallocate(mach_task_self(), host);
    return success;
}
