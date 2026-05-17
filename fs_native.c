#include "moonbit.h"

#include <dirent.h>
#include <errno.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

typedef struct {
  int64_t size;
  int mode;
} readdirp_stat_result_t;

static int readdirp_last_errno = 0;

static moonbit_bytes_t readdirp_bytes_from_cstr(const char *text) {
  size_t len = strlen(text);
  moonbit_bytes_t bytes = moonbit_make_bytes((int32_t)len, 0);
  if (len > 0) {
    memcpy(bytes, text, len);
  }
  return bytes;
}

static void readdirp_set_errno(int err) { readdirp_last_errno = err; }

static char *readdirp_cstring_from_bytes(moonbit_bytes_t bytes) {
  size_t len = (size_t)Moonbit_array_length(bytes);
  char *text = (char *)malloc(len + 1);
  if (text == NULL) {
    readdirp_set_errno(ENOMEM);
    return NULL;
  }
  if (len > 0) {
    memcpy(text, bytes, len);
  }
  text[len] = '\0';
  return text;
}

MOONBIT_FFI_EXPORT moonbit_bytes_t readdirp_last_error_message(void) {
  int err = readdirp_last_errno == 0 ? errno : readdirp_last_errno;
  return readdirp_bytes_from_cstr(strerror(err));
}

MOONBIT_FFI_EXPORT int readdirp_names_is_null(void *names) {
  return names == NULL;
}

MOONBIT_FFI_EXPORT moonbit_bytes_t *
readdirp_read_dir_all(moonbit_bytes_t path) {
  char *path_text = readdirp_cstring_from_bytes(path);
  if (path_text == NULL) {
    return NULL;
  }

  DIR *dir = opendir(path_text);
  free(path_text);
  if (dir == NULL) {
    readdirp_set_errno(errno);
    return NULL;
  }

  int count = 0;
  struct dirent *entry = NULL;
  while ((entry = readdir(dir)) != NULL) {
    if (strcmp(entry->d_name, ".") != 0 && strcmp(entry->d_name, "..") != 0) {
      count += 1;
    }
  }
  rewinddir(dir);

  moonbit_bytes_t *result =
      (moonbit_bytes_t *)moonbit_make_ref_array(count, NULL);
  if (result == NULL) {
    closedir(dir);
    readdirp_set_errno(ENOMEM);
    return NULL;
  }

  int index = 0;
  while ((entry = readdir(dir)) != NULL) {
    if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) {
      continue;
    }
    result[index] = readdirp_bytes_from_cstr(entry->d_name);
    index += 1;
  }

  closedir(dir);
  readdirp_set_errno(0);
  return result;
}

MOONBIT_FFI_EXPORT readdirp_stat_result_t *
readdirp_stat_path(moonbit_bytes_t path, int follow_symlink) {
  char *path_text = readdirp_cstring_from_bytes(path);
  if (path_text == NULL) {
    return NULL;
  }

  struct stat stat_result;
  int status = follow_symlink ? stat(path_text, &stat_result)
                              : lstat(path_text, &stat_result);
  free(path_text);
  if (status != 0) {
    readdirp_set_errno(errno);
    return NULL;
  }

  readdirp_stat_result_t *result =
      (readdirp_stat_result_t *)malloc(sizeof(readdirp_stat_result_t));
  if (result == NULL) {
    readdirp_set_errno(ENOMEM);
    return NULL;
  }

  result->size = (int64_t)stat_result.st_size;
  result->mode = (int)stat_result.st_mode;
  readdirp_set_errno(0);
  return result;
}

MOONBIT_FFI_EXPORT int readdirp_stat_is_null(void *stat_result) {
  return stat_result == NULL;
}

MOONBIT_FFI_EXPORT int64_t
readdirp_stat_size(readdirp_stat_result_t *stat_result) {
  return stat_result->size;
}

MOONBIT_FFI_EXPORT int readdirp_stat_mode(
    readdirp_stat_result_t *stat_result) {
  return stat_result->mode;
}

MOONBIT_FFI_EXPORT int readdirp_test_create_dir(moonbit_bytes_t path) {
  char *path_text = readdirp_cstring_from_bytes(path);
  if (path_text == NULL) {
    return -1;
  }

  int status = mkdir(path_text, 0777);
  int err = errno;
  free(path_text);
  if (status == 0 || err == EEXIST) {
    readdirp_set_errno(0);
    return 0;
  }
  readdirp_set_errno(err);
  return -1;
}

MOONBIT_FFI_EXPORT int readdirp_test_write_file(moonbit_bytes_t path,
                                                moonbit_bytes_t contents) {
  char *path_text = readdirp_cstring_from_bytes(path);
  if (path_text == NULL) {
    return -1;
  }

  FILE *file = fopen(path_text, "wb");
  free(path_text);
  if (file == NULL) {
    readdirp_set_errno(errno);
    return -1;
  }

  size_t length = (size_t)Moonbit_array_length(contents);
  size_t written = fwrite(contents, 1, length, file);
  int close_status = fclose(file);
  if (written != length || close_status != 0) {
    readdirp_set_errno(errno);
    return -1;
  }

  readdirp_set_errno(0);
  return 0;
}

static int readdirp_join_path(char *out, size_t out_size, const char *left,
                              const char *right) {
  size_t left_len = strlen(left);
  const char *sep = left_len > 0 && left[left_len - 1] == '/' ? "" : "/";
  int written = snprintf(out, out_size, "%s%s%s", left, sep, right);
  return written >= 0 && (size_t)written < out_size;
}

static int readdirp_remove_tree_path(const char *path) {
  struct stat info;
  if (lstat(path, &info) != 0) {
    if (errno == ENOENT) {
      return 0;
    }
    return -1;
  }

  if (!S_ISDIR(info.st_mode) || S_ISLNK(info.st_mode)) {
    return unlink(path);
  }

  DIR *dir = opendir(path);
  if (dir == NULL) {
    return -1;
  }

  struct dirent *entry = NULL;
  while ((entry = readdir(dir)) != NULL) {
    if (strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0) {
      continue;
    }

    char child[PATH_MAX];
    if (!readdirp_join_path(child, sizeof(child), path, entry->d_name)) {
      closedir(dir);
      errno = ENAMETOOLONG;
      return -1;
    }

    if (readdirp_remove_tree_path(child) != 0) {
      int err = errno;
      closedir(dir);
      errno = err;
      return -1;
    }
  }

  if (closedir(dir) != 0) {
    return -1;
  }
  return rmdir(path);
}

MOONBIT_FFI_EXPORT int readdirp_test_remove_tree(moonbit_bytes_t path) {
  char *path_text = readdirp_cstring_from_bytes(path);
  if (path_text == NULL) {
    return -1;
  }

  int status = readdirp_remove_tree_path(path_text);
  int err = errno;
  free(path_text);
  if (status == 0) {
    readdirp_set_errno(0);
    return 0;
  }
  readdirp_set_errno(err);
  return -1;
}

MOONBIT_FFI_EXPORT int readdirp_test_symlink(moonbit_bytes_t target,
                                             moonbit_bytes_t link_path) {
  char *target_text = readdirp_cstring_from_bytes(target);
  if (target_text == NULL) {
    return -1;
  }
  char *link_path_text = readdirp_cstring_from_bytes(link_path);
  if (link_path_text == NULL) {
    free(target_text);
    return -1;
  }

  int status = symlink(target_text, link_path_text);
  int err = errno;
  free(target_text);
  free(link_path_text);
  if (status == 0) {
    readdirp_set_errno(0);
    return 0;
  }
  readdirp_set_errno(err);
  return -1;
}
