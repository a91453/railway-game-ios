// Extract only .bin entries from a Railway cabinet into a local private folder.
// Uses the system libarchive API; no archive content is embedded or uploaded.
//
// cc -std=c11 -O2 -Wall -Wextra extract_cab_bins.c -larchive -o /tmp/railway-cab-bins
// /tmp/railway-cab-bins /private/RailwayFamily.cab /private/bin
#include <archive.h>
#include <archive_entry.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int is_safe_bin(const char* path) {
    if (!path) return 0;
    const size_t size = strlen(path);
    return size > 4 && strcmp(path + size - 4, ".bin") == 0
        && !strchr(path, '/') && !strchr(path, '\\') && !strstr(path, "..");
}
int main(int argc, char** argv) {
    if (argc != 3) {
        fprintf(stderr, "Usage: railway-cab-bins input.cab output-directory\n");
        return 2;
    }
    struct archive* reader = archive_read_new();
    if (!reader) return 3;
    archive_read_support_format_cab(reader);
    archive_read_support_filter_all(reader);
    int code = archive_read_open_filename(reader, argv[1], 1024 * 1024);
    if (code != ARCHIVE_OK) {
        fprintf(stderr, "CAB open failed: %s\n", archive_error_string(reader));
        archive_read_free(reader);
        return 3;
    }
    struct archive_entry* entry = NULL;
    uint8_t data[1024 * 1024];
    size_t count = 0;
    long long bytes = 0;
    while ((code = archive_read_next_header(reader, &entry)) == ARCHIVE_OK) {
        const char* name = archive_entry_pathname(entry);
        if (!is_safe_bin(name)) {
            archive_read_data_skip(reader);
            continue;
        }
        char destination[4096];
        const int n = snprintf(destination, sizeof(destination), "%s/%s", argv[2], name);
        if (n <= 0 || (size_t)n >= sizeof(destination)) {
            fprintf(stderr, "Output path too long for %s\n", name);
            archive_read_free(reader);
            return 4;
        }
        const long long expected = archive_entry_size(entry);
        FILE* output = fopen(destination, "wb");
        if (!output) {
            perror(destination);
            archive_read_free(reader);
            return 4;
        }
        long long received = 0;
        for (;;) {
            la_ssize_t got = archive_read_data(reader, data, sizeof(data));
            if (got < 0) {
                fprintf(stderr, "CAB read error (%s): %s\n", name, archive_error_string(reader));
                fclose(output);
                remove(destination);
                archive_read_free(reader);
                return 5;
            }
            if (got == 0) break;
            if (fwrite(data, 1, (size_t)got, output) != (size_t)got) {
                perror("Write error");
                fclose(output);
                remove(destination);
                archive_read_free(reader);
                return 5;
            }
            received += got;
        }
        fclose(output);
        if (expected >= 0 && received != expected) {
            fprintf(stderr, "CAB item size mismatch for %s\n", name);
            remove(destination);
            archive_read_free(reader);
            return 6;
        }
        printf("%s %lld\n", name, received);
        ++count;
        bytes += received;
    }
    if (code != ARCHIVE_EOF) {
        fprintf(stderr, "CAB iteration failed: %s\n", archive_error_string(reader));
        archive_read_free(reader);
        return 7;
    }
    printf("Total .bin: %zu, bytes: %lld\n", count, bytes);
    archive_read_free(reader);
    return 0;
}
