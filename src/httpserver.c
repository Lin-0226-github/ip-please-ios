#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <unistd.h>
#include <errno.h>
#include <pthread.h>
#include <stdint.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <netinet/in.h>
#include <arpa/inet.h>

#include "httpserver.h"

#ifndef MSG_NOSIGNAL
#define MSG_NOSIGNAL 0
#endif

static char g_root[1024];
static int g_port = -1;
static int g_listen = -1;

static const char *mime_for(const char *path) {
  const char *dot = strrchr(path, '.');
  if (!dot) return "application/octet-stream";
  if (!strcasecmp(dot, ".html") || !strcasecmp(dot, ".htm")) return "text/html; charset=utf-8";
  if (!strcasecmp(dot, ".js"))  return "application/javascript; charset=utf-8";
  if (!strcasecmp(dot, ".mjs")) return "application/javascript; charset=utf-8";
  if (!strcasecmp(dot, ".css")) return "text/css; charset=utf-8";
  if (!strcasecmp(dot, ".json")) return "application/json; charset=utf-8";
  if (!strcasecmp(dot, ".txt")) return "text/plain; charset=utf-8";
  if (!strcasecmp(dot, ".svg")) return "image/svg+xml";
  if (!strcasecmp(dot, ".png")) return "image/png";
  if (!strcasecmp(dot, ".jpg") || !strcasecmp(dot, ".jpeg")) return "image/jpeg";
  if (!strcasecmp(dot, ".gif")) return "image/gif";
  if (!strcasecmp(dot, ".webp")) return "image/webp";
  if (!strcasecmp(dot, ".ico")) return "image/x-icon";
  if (!strcasecmp(dot, ".wav")) return "audio/wav";
  if (!strcasecmp(dot, ".mp3")) return "audio/mpeg";
  if (!strcasecmp(dot, ".ogg")) return "audio/ogg";
  if (!strcasecmp(dot, ".woff")) return "font/woff";
  if (!strcasecmp(dot, ".woff2")) return "font/woff2";
  if (!strcasecmp(dot, ".ttf")) return "font/ttf";
  return "application/octet-stream";
}

static void send_all(int fd, const void *buf, size_t len) {
  const char *p = (const char *)buf;
  while (len > 0) {
    ssize_t n = send(fd, p, len, MSG_NOSIGNAL);
    if (n > 0) { p += n; len -= (size_t)n; continue; }
    if (n < 0 && (errno == EINTR)) continue;
    break;
  }
}

static void send_status(int fd, const char *status, const char *body) {
  char head[256];
  size_t blen = body ? strlen(body) : 0;
  int hl = snprintf(head, sizeof head,
                    "HTTP/1.1 %s\r\nContent-Type: text/plain; charset=utf-8\r\n"
                    "Content-Length: %zu\r\nConnection: close\r\n\r\n",
                    status, blen);
  if (hl > 0) send_all(fd, head, (size_t)hl);
  if (blen) send_all(fd, body, blen);
}

static void url_decode(char *dst, const char *src, size_t dstlen) {
  size_t d = 0;
  while (*src && d + 1 < dstlen) {
    if (*src == '%' && src[1] && src[2]) {
      char hex[3] = { src[1], src[2], 0 };
      char *end = NULL;
      long v = strtol(hex, &end, 16);
      if (end && *end == 0) { dst[d++] = (char)v; src += 3; continue; }
    }
    dst[d++] = *src++;
  }
  dst[d] = 0;
}

static void *conn_main(void *arg) {
  int fd = (int)(intptr_t)arg;
  pthread_detach(pthread_self());

#ifdef SO_NOSIGPIPE
  int one = 1;
  setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof one);
#endif
  struct timeval tv;
  tv.tv_sec = 8;
  tv.tv_usec = 0;
  setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);

  char req[8192];
  size_t len = 0;
  req[0] = 0;
  while (len + 1 < sizeof req) {
    ssize_t n = recv(fd, req + len, sizeof req - 1 - len, 0);
    if (n <= 0) break;
    len += (size_t)n;
    req[len] = 0;
    if (strstr(req, "\r\n\r\n")) break;
  }
  if (len == 0) { close(fd); return NULL; }

  char method[16] = {0}, rawpath[4096] = {0};
  if (sscanf(req, "%15s %4095s", method, rawpath) != 2) {
    send_status(fd, "400 Bad Request", "bad request");
    close(fd);
    return NULL;
  }

  int is_head = (strcmp(method, "HEAD") == 0);
  if (strcmp(method, "GET") != 0 && !is_head) {
    send_status(fd, "405 Method Not Allowed", "method not allowed");
    close(fd);
    return NULL;
  }

  /* strip query string / fragment */
  char *q = strpbrk(rawpath, "?#");
  if (q) *q = 0;

  char path[4096];
  url_decode(path, rawpath, sizeof path);

  if (strstr(path, "..")) {
    send_status(fd, "403 Forbidden", "forbidden");
    close(fd);
    return NULL;
  }
  if (path[0] != '/') {
    size_t l = strlen(path);
    if (l + 2 > sizeof path) l = sizeof path - 2;
    memmove(path + 1, path, l);
    path[0] = '/';
    path[l + 1] = 0;
  }

  char full[8192];
  size_t plen = strlen(path);
  if (plen == 0 || path[plen - 1] == '/') {
    snprintf(full, sizeof full, "%s%s%s", g_root, path, "index.html");
  } else {
    snprintf(full, sizeof full, "%s%s", g_root, path);
  }

  struct stat st;
  if (stat(full, &st) != 0) {
    send_status(fd, "404 Not Found", "not found");
    close(fd);
    return NULL;
  }
  if (S_ISDIR(st.st_mode)) {
    snprintf(full, sizeof full, "%s%s%s", g_root, path, "/index.html");
    if (stat(full, &st) != 0) {
      send_status(fd, "404 Not Found", "not found");
      close(fd);
      return NULL;
    }
  }

  FILE *f = fopen(full, "rb");
  if (!f) {
    send_status(fd, "403 Forbidden", "forbidden");
    close(fd);
    return NULL;
  }
  long fsize = (long)st.st_size;
  if (fsize < 0) fsize = 0;

  char head[512];
  int hl = snprintf(head, sizeof head,
                    "HTTP/1.1 200 OK\r\nContent-Type: %s\r\nContent-Length: %ld\r\n"
                    "Cache-Control: no-cache\r\nConnection: close\r\n\r\n",
                    mime_for(full), fsize);
  if (hl > 0) send_all(fd, head, (size_t)hl);

  if (!is_head && fsize > 0) {
    char buf[65536];
    size_t got;
    while ((got = fread(buf, 1, sizeof buf, f)) > 0) send_all(fd, buf, got);
  }
  fclose(f);
  shutdown(fd, SHUT_WR);
  close(fd);
  return NULL;
}

static void *accept_main(void *arg) {
  (void)arg;
  for (;;) {
    int c = accept(g_listen, NULL, NULL);
    if (c < 0) {
      if (errno == EINTR) continue;
      break;
    }
    pthread_t th;
    if (pthread_create(&th, NULL, conn_main, (void *)(intptr_t)c) != 0) {
      close(c);
    }
  }
  return NULL;
}

int hs_start(const char *root, int firstPort, int tries) {
  if (!root) return -1;
  snprintf(g_root, sizeof g_root, "%s", root);
  size_t rl = strlen(g_root);
  while (rl > 1 && g_root[rl - 1] == '/') g_root[--rl] = 0;

  int fd = socket(AF_INET, SOCK_STREAM, 0);
  if (fd < 0) return -1;
  int one = 1;
  setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);

  struct sockaddr_in addr;
  memset(&addr, 0, sizeof addr);
  addr.sin_family = AF_INET;
  addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);

  int bound = -1;
  for (int i = 0; i < (tries > 0 ? tries : 1); i++) {
    addr.sin_port = htons((uint16_t)(firstPort + i));
    if (bind(fd, (struct sockaddr *)&addr, sizeof addr) == 0) { bound = firstPort + i; break; }
  }
  if (bound < 0) { close(fd); return -1; }
  if (listen(fd, 64) != 0) { close(fd); return -1; }

  g_listen = fd;
  g_port = bound;

  pthread_t th;
  if (pthread_create(&th, NULL, accept_main, NULL) != 0) {
    close(fd);
    g_listen = -1;
    g_port = -1;
    return -1;
  }
  pthread_detach(th);
  return bound;
}

int hs_port(void) { return g_port; }
