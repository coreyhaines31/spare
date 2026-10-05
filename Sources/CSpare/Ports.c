#include "CSpare.h"
#include <libproc.h>
#include <sys/proc_info.h>
#include <stdlib.h>
#include <arpa/inet.h>

int spare_ports(int pid, uint16_t *ports, int capacity) {
    int size = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, NULL, 0);
    if (size <= 0 || size > 1024 * 1024) return 0;
    size += 32 * sizeof(struct proc_fdinfo);
    struct proc_fdinfo *fds = malloc(size);
    if (!fds) return 0;
    int bytes = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, fds, size);
    int count = 0;
    for (int i = 0; i < bytes / (int)sizeof(*fds) && count < capacity; i++) {
        if (fds[i].proc_fdtype != PROX_FDTYPE_SOCKET) continue;
        struct socket_fdinfo socket;
        if (proc_pidfdinfo(pid, fds[i].proc_fd, PROC_PIDFDSOCKETINFO, &socket, sizeof(socket)) != sizeof(socket)) continue;
        if (socket.psi.soi_kind != SOCKINFO_TCP || socket.psi.soi_proto.pri_tcp.tcpsi_state != TSI_S_LISTEN) continue;
        uint16_t port = ntohs((uint16_t)socket.psi.soi_proto.pri_tcp.tcpsi_ini.insi_lport);
        bool exists = false;
        for (int j = 0; j < count; j++) if (ports[j] == port) exists = true;
        if (!exists) ports[count++] = port;
    }
    free(fds);
    return count;
}
