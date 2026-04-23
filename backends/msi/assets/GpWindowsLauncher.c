#define _CRT_SECURE_NO_WARNINGS

#include <windows.h>
#include <shellapi.h>
#include <shlwapi.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

#define GP_MAX_PATH 32768
#define GP_MAX_LINE 4096
#define GP_MAX_ITEMS 64
#define GP_MAX_KEY 128
#define GP_MAX_TITLE 256

typedef struct GPEnvEntry {
    wchar_t key[GP_MAX_KEY];
    wchar_t value[GP_MAX_PATH];
    int policy;
} GPEnvEntry;

typedef struct GPAppDefaultEntry {
    wchar_t key[GP_MAX_KEY];
    wchar_t value[GP_MAX_PATH];
} GPAppDefaultEntry;

enum {
    GP_ENV_OVERRIDE = 0,
    GP_ENV_IF_UNSET = 1
};

typedef struct GPLauncherConfig {
    wchar_t displayName[GP_MAX_TITLE];
    wchar_t entryRelativePath[GP_MAX_PATH];
    wchar_t workingDirectoryRelative[GP_MAX_PATH];
    wchar_t runtimeRootRelative[GP_MAX_PATH];
    wchar_t appRootRelative[GP_MAX_PATH];
    wchar_t metadataRootRelative[GP_MAX_PATH];
    wchar_t fallbackRuntimeRoot[GP_MAX_PATH];
    wchar_t pathPrepend[GP_MAX_ITEMS][GP_MAX_PATH];
    int pathPrependCount;
    wchar_t baseArgument[GP_MAX_ITEMS][GP_MAX_PATH];
    int baseArgumentCount;
    wchar_t appDefaultsDomain[GP_MAX_PATH];
    GPAppDefaultEntry appDefaults[GP_MAX_ITEMS];
    int appDefaultsCount;
    GPEnvEntry env[GP_MAX_ITEMS];
    int envCount;
} GPLauncherConfig;

typedef struct GPLauncherState {
    wchar_t launcherPath[GP_MAX_PATH];
    wchar_t installRoot[GP_MAX_PATH];
    wchar_t configPath[GP_MAX_PATH];
    wchar_t appPath[GP_MAX_PATH];
    wchar_t appRoot[GP_MAX_PATH];
    wchar_t metadataRoot[GP_MAX_PATH];
    wchar_t localRuntimeRoot[GP_MAX_PATH];
    wchar_t localRuntimeBin[GP_MAX_PATH];
    wchar_t runtimeRoot[GP_MAX_PATH];
    wchar_t runtimeBin[GP_MAX_PATH];
    wchar_t workingDirectory[GP_MAX_PATH];
    wchar_t expandedPathSpec[GP_MAX_PATH];
    wchar_t resolvedPathSpec[GP_MAX_PATH];
    wchar_t commandBuffer[GP_MAX_PATH];
    wchar_t errorBuffer[GP_MAX_PATH];
    GPLauncherConfig config;
} GPLauncherState;

static void GPShowError(const wchar_t *title, const wchar_t *message)
{
    MessageBoxW(NULL, message, title, MB_OK | MB_ICONERROR);
}

static BOOL GPFileExists(const wchar_t *path)
{
    DWORD attrs = GetFileAttributesW(path);
    return attrs != INVALID_FILE_ATTRIBUTES && (attrs & FILE_ATTRIBUTE_DIRECTORY) == 0;
}

static BOOL GPDirectoryExists(const wchar_t *path)
{
    DWORD attrs = GetFileAttributesW(path);
    return attrs != INVALID_FILE_ATTRIBUTES && (attrs & FILE_ATTRIBUTE_DIRECTORY) != 0;
}

static BOOL GPSetWideValue(wchar_t *dest, size_t destCount, const wchar_t *value)
{
    if (dest == NULL || destCount == 0 || value == NULL) {
        return FALSE;
    }
    if (wcslen(value) + 1 > destCount) {
        return FALSE;
    }
    wcscpy(dest, value);
    return TRUE;
}

static BOOL GPJoinPath(wchar_t *dest, size_t destCount, const wchar_t *left, const wchar_t *right)
{
    int written = 0;
    if (left == NULL || right == NULL) {
        return FALSE;
    }
    if (right[0] == L'\0' || wcscmp(right, L".") == 0) {
        return GPSetWideValue(dest, destCount, left);
    }
    written = swprintf(dest, destCount, L"%ls\\%ls", left, right);
    return written >= 0 && (size_t)written < destCount;
}

static void GPTrimAscii(char *text)
{
    size_t length = 0;
    char *start = text;
    char *end = NULL;

    while (*start == ' ' || *start == '\t' || *start == '\r' || *start == '\n') {
        start++;
    }

    if (start != text) {
        memmove(text, start, strlen(start) + 1);
    }

    length = strlen(text);
    if (length == 0) {
        return;
    }

    end = text + length - 1;
    while (end >= text && (*end == ' ' || *end == '\t' || *end == '\r' || *end == '\n')) {
        *end-- = '\0';
    }
}

static BOOL GPUtf8ToWide(const char *input, wchar_t *dest, size_t destCount)
{
    int required = 0;
    if (input == NULL || dest == NULL || destCount == 0) {
        return FALSE;
    }
    required = MultiByteToWideChar(CP_UTF8, 0, input, -1, NULL, 0);
    if (required <= 0 || (size_t)required > destCount) {
        return FALSE;
    }
    return MultiByteToWideChar(CP_UTF8, 0, input, -1, dest, (int)destCount) > 0;
}

static BOOL GPQuoteArgument(wchar_t *dest, size_t destCount, const wchar_t *arg)
{
    size_t len = 0;

    if (destCount < 3) {
        return FALSE;
    }

    dest[len++] = L'"';
    while (*arg != L'\0') {
        unsigned backslashes = 0;
        while (*arg == L'\\') {
            backslashes++;
            arg++;
        }

        if (*arg == L'\0') {
            while (backslashes-- > 0) {
                if (len + 2 >= destCount) {
                    return FALSE;
                }
                dest[len++] = L'\\';
                dest[len++] = L'\\';
            }
            break;
        }

        if (*arg == L'"') {
            while (backslashes-- > 0) {
                if (len + 2 >= destCount) {
                    return FALSE;
                }
                dest[len++] = L'\\';
                dest[len++] = L'\\';
            }
            if (len + 2 >= destCount) {
                return FALSE;
            }
            dest[len++] = L'\\';
            dest[len++] = L'"';
            arg++;
            continue;
        }

        while (backslashes-- > 0) {
            if (len + 1 >= destCount) {
                return FALSE;
            }
            dest[len++] = L'\\';
        }
        if (len + 1 >= destCount) {
            return FALSE;
        }
        dest[len++] = *arg++;
    }

    if (len + 2 > destCount) {
        return FALSE;
    }
    dest[len++] = L'"';
    dest[len] = L'\0';
    return TRUE;
}

static BOOL GPParseKeyValue(char *line, char **keyOut, char **valueOut)
{
    char *separator = strchr(line, '=');
    if (separator == NULL) {
        return FALSE;
    }

    *separator = '\0';
    *keyOut = line;
    *valueOut = separator + 1;
    GPTrimAscii(*keyOut);
    GPTrimAscii(*valueOut);
    return TRUE;
}

static BOOL GPAddPathPrepend(GPLauncherConfig *config, const char *value)
{
    if (config->pathPrependCount >= GP_MAX_ITEMS) {
        return FALSE;
    }
    return GPUtf8ToWide(value,
                        config->pathPrepend[config->pathPrependCount++],
                        GP_MAX_PATH);
}

static BOOL GPAddBaseArgument(GPLauncherConfig *config, const char *value)
{
    if (config->baseArgumentCount >= GP_MAX_ITEMS) {
        return FALSE;
    }
    return GPUtf8ToWide(value,
                        config->baseArgument[config->baseArgumentCount++],
                        GP_MAX_PATH);
}

static BOOL GPAddEnvEntry(GPLauncherConfig *config, const char *value)
{
    char buffer[GP_MAX_LINE];
    char *policyText = NULL;
    char *policySeparator = NULL;
    char *equalsSeparator = NULL;
    char *key = NULL;
    char *entryValue = NULL;

    if (config->envCount >= GP_MAX_ITEMS) {
        return FALSE;
    }

    strncpy(buffer, value, sizeof(buffer) - 1);
    buffer[sizeof(buffer) - 1] = '\0';
    policyText = buffer;
    equalsSeparator = strchr(buffer, '=');
    policySeparator = strchr(buffer, '|');
    if (policySeparator != NULL && equalsSeparator != NULL && policySeparator < equalsSeparator) {
        *policySeparator = '\0';
        key = policySeparator + 1;
    } else {
        key = buffer;
    }

    if (!GPParseKeyValue(key, &key, &entryValue)) {
        return FALSE;
    }

    if (!GPUtf8ToWide(key, config->env[config->envCount].key, GP_MAX_KEY)) {
        return FALSE;
    }
    if (!GPUtf8ToWide(entryValue, config->env[config->envCount].value, GP_MAX_PATH)) {
        return FALSE;
    }
    if (strcmp(policyText, "override") == 0 || policySeparator == NULL) {
        config->env[config->envCount].policy = GP_ENV_OVERRIDE;
    } else if (strcmp(policyText, "ifUnset") == 0) {
        config->env[config->envCount].policy = GP_ENV_IF_UNSET;
    } else {
        return FALSE;
    }
    config->envCount++;
    return TRUE;
}

static BOOL GPAddAppDefaultEntry(GPLauncherConfig *config, const char *value)
{
    char buffer[GP_MAX_LINE];
    char *key = NULL;
    char *entryValue = NULL;

    if (config->appDefaultsCount >= GP_MAX_ITEMS) {
        return FALSE;
    }

    strncpy(buffer, value, sizeof(buffer) - 1);
    buffer[sizeof(buffer) - 1] = '\0';
    if (!GPParseKeyValue(buffer, &key, &entryValue)) {
        return FALSE;
    }

    if (!GPUtf8ToWide(key, config->appDefaults[config->appDefaultsCount].key, GP_MAX_KEY)) {
        return FALSE;
    }
    if (!GPUtf8ToWide(entryValue, config->appDefaults[config->appDefaultsCount].value, GP_MAX_PATH)) {
        return FALSE;
    }

    config->appDefaultsCount++;
    return TRUE;
}

static BOOL GPApplyConfigLine(GPLauncherConfig *config, char *line)
{
    char *key = NULL;
    char *value = NULL;

    GPTrimAscii(line);
    if (line[0] == '\0' || line[0] == '#' || line[0] == ';') {
        return TRUE;
    }

    if (!GPParseKeyValue(line, &key, &value)) {
        return FALSE;
    }

    if (strcmp(key, "displayName") == 0) {
        return GPUtf8ToWide(value, config->displayName, GP_MAX_TITLE);
    }
    if (strcmp(key, "entryRelativePath") == 0) {
        return GPUtf8ToWide(value, config->entryRelativePath, GP_MAX_PATH);
    }
    if (strcmp(key, "workingDirectoryRelative") == 0) {
        return GPUtf8ToWide(value, config->workingDirectoryRelative, GP_MAX_PATH);
    }
    if (strcmp(key, "runtimeRootRelative") == 0) {
        return GPUtf8ToWide(value, config->runtimeRootRelative, GP_MAX_PATH);
    }
    if (strcmp(key, "appRootRelative") == 0) {
        return GPUtf8ToWide(value, config->appRootRelative, GP_MAX_PATH);
    }
    if (strcmp(key, "metadataRootRelative") == 0) {
        return GPUtf8ToWide(value, config->metadataRootRelative, GP_MAX_PATH);
    }
    if (strcmp(key, "fallbackRuntimeRoot") == 0) {
        return GPUtf8ToWide(value, config->fallbackRuntimeRoot, GP_MAX_PATH);
    }
    if (strcmp(key, "pathPrepend") == 0) {
        return GPAddPathPrepend(config, value);
    }
    if (strcmp(key, "baseArgument") == 0) {
        return GPAddBaseArgument(config, value);
    }
    if (strcmp(key, "appDefaultsDomain") == 0) {
        return GPUtf8ToWide(value, config->appDefaultsDomain, GP_MAX_PATH);
    }
    if (strcmp(key, "appDefault") == 0) {
        return GPAddAppDefaultEntry(config, value);
    }
    if (strcmp(key, "env") == 0) {
        return GPAddEnvEntry(config, value);
    }
    return TRUE;
}

static BOOL GPLoadConfig(const wchar_t *configPath, GPLauncherConfig *config)
{
    FILE *stream = NULL;
    char line[GP_MAX_LINE];

    ZeroMemory(config, sizeof(*config));
    GPSetWideValue(config->workingDirectoryRelative, GP_MAX_PATH, L".");
    GPSetWideValue(config->runtimeRootRelative, GP_MAX_PATH, L"runtime");
    GPSetWideValue(config->appRootRelative, GP_MAX_PATH, L"app");
    GPSetWideValue(config->metadataRootRelative, GP_MAX_PATH, L"metadata");
    GPSetWideValue(config->displayName, GP_MAX_TITLE, L"GNUstep Application");

    stream = _wfopen(configPath, L"rb");
    if (stream == NULL) {
        return FALSE;
    }

    while (fgets(line, sizeof(line), stream) != NULL) {
        if (!GPApplyConfigLine(config, line)) {
            fclose(stream);
            return FALSE;
        }
    }

    fclose(stream);
    return config->entryRelativePath[0] != L'\0';
}

static BOOL GPAppendText(wchar_t *dest, size_t destCount, size_t *used, const wchar_t *text)
{
    size_t textLen = 0;
    if (dest == NULL || used == NULL || text == NULL) {
        return FALSE;
    }
    textLen = wcslen(text);
    if (*used + textLen + 1 > destCount) {
        return FALSE;
    }
    wcscpy(dest + *used, text);
    *used += textLen;
    return TRUE;
}

static BOOL GPExpandTokens(wchar_t *dest,
                           size_t destCount,
                           const wchar_t *input,
                           const wchar_t *installRoot,
                           const wchar_t *appRoot,
                           const wchar_t *runtimeRoot,
                           const wchar_t *metadataRoot)
{
    const wchar_t *cursor = input;
    size_t used = 0;

    dest[0] = L'\0';

    while (*cursor != L'\0') {
        if (wcsncmp(cursor, L"{@installRoot}", 14) == 0) {
            if (!GPAppendText(dest, destCount, &used, installRoot)) {
                return FALSE;
            }
            cursor += 14;
            continue;
        }
        if (wcsncmp(cursor, L"{@appRoot}", 10) == 0) {
            if (!GPAppendText(dest, destCount, &used, appRoot)) {
                return FALSE;
            }
            cursor += 10;
            continue;
        }
        if (wcsncmp(cursor, L"{@runtimeRoot}", 14) == 0) {
            if (!GPAppendText(dest, destCount, &used, runtimeRoot)) {
                return FALSE;
            }
            cursor += 14;
            continue;
        }
        if (wcsncmp(cursor, L"{@metadataRoot}", 15) == 0) {
            if (!GPAppendText(dest, destCount, &used, metadataRoot)) {
                return FALSE;
            }
            cursor += 15;
            continue;
        }
        if (used + 2 > destCount) {
            return FALSE;
        }
        dest[used++] = *cursor++;
        dest[used] = L'\0';
    }

    return TRUE;
}

static BOOL GPResolvePathSpec(wchar_t *dest, size_t destCount, const wchar_t *installRoot, const wchar_t *spec)
{
    if (spec[0] == L'\0' || wcscmp(spec, L".") == 0) {
        return GPSetWideValue(dest, destCount, installRoot);
    }

    if (PathIsRelativeW(spec)) {
        return GPJoinPath(dest, destCount, installRoot, spec);
    }

    return GPSetWideValue(dest, destCount, spec);
}

static BOOL GPPrependPath(const wchar_t *binPath)
{
    DWORD currentLen = GetEnvironmentVariableW(L"PATH", NULL, 0);
    wchar_t *current = NULL;
    wchar_t *updated = NULL;
    size_t updatedCount = 0;
    BOOL ok = FALSE;

    if (currentLen == 0) {
        currentLen = 1;
    }

    current = (wchar_t *)HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, currentLen * sizeof(wchar_t));
    if (current == NULL) {
        return FALSE;
    }

    if (currentLen > 1) {
        GetEnvironmentVariableW(L"PATH", current, currentLen);
    } else {
        current[0] = L'\0';
    }

    updatedCount = wcslen(binPath) + 1 + wcslen(current) + 1;
    updated = (wchar_t *)HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, updatedCount * sizeof(wchar_t));
    if (updated == NULL) {
        HeapFree(GetProcessHeap(), 0, current);
        return FALSE;
    }

    swprintf(updated, updatedCount, L"%ls;%ls", binPath, current);
    ok = SetEnvironmentVariableW(L"PATH", updated);

    HeapFree(GetProcessHeap(), 0, updated);
    HeapFree(GetProcessHeap(), 0, current);
    return ok;
}

static BOOL GPConfigureFontconfig(const wchar_t *runtimeRoot)
{
    wchar_t fontconfigPath[GP_MAX_PATH];
    wchar_t fontconfigFile[GP_MAX_PATH];

    if (!GPJoinPath(fontconfigPath, GP_MAX_PATH, runtimeRoot, L"etc\\fonts")) {
        return FALSE;
    }
    if (!GPJoinPath(fontconfigFile, GP_MAX_PATH, fontconfigPath, L"fonts.conf")) {
        return FALSE;
    }

    if (GPFileExists(fontconfigFile)) {
        if (!SetEnvironmentVariableW(L"FONTCONFIG_PATH", fontconfigPath)) {
            return FALSE;
        }
        if (!SetEnvironmentVariableW(L"FONTCONFIG_FILE", fontconfigFile)) {
            return FALSE;
        }
    }

    return TRUE;
}

static BOOL GPEnvironmentVariableExists(const wchar_t *key)
{
    wchar_t scratch[2];
    DWORD result = 0;

    SetLastError(ERROR_SUCCESS);
    result = GetEnvironmentVariableW(key, scratch, 2);
    if (result == 0 && GetLastError() == ERROR_ENVVAR_NOT_FOUND) {
        return FALSE;
    }

    return TRUE;
}

static BOOL GPBuildChildCommandLine(wchar_t *dest,
                                    size_t destCount,
                                    const wchar_t *appPath,
                                    const GPLauncherConfig *config)
{
    int argc = 0;
    int i = 0;
    size_t used = 0;
    LPWSTR *argv = CommandLineToArgvW(GetCommandLineW(), &argc);
    wchar_t quotedArg[GP_MAX_PATH];

    if (argv == NULL) {
        return FALSE;
    }

    if (!GPQuoteArgument(quotedArg, GP_MAX_PATH, appPath)) {
        LocalFree(argv);
        return FALSE;
    }

    used = wcslen(quotedArg);
    if (used + 1 > destCount) {
        LocalFree(argv);
        return FALSE;
    }
    wcscpy(dest, quotedArg);

    for (i = 0; i < config->baseArgumentCount; i++) {
        size_t quotedLen = 0;
        if (!GPQuoteArgument(quotedArg, GP_MAX_PATH, config->baseArgument[i])) {
            LocalFree(argv);
            return FALSE;
        }
        quotedLen = wcslen(quotedArg);
        if (used + 1 + quotedLen + 1 > destCount) {
            LocalFree(argv);
            return FALSE;
        }
        dest[used++] = L' ';
        wcscpy(dest + used, quotedArg);
        used += quotedLen;
    }

    for (i = 1; i < argc; i++) {
        size_t quotedLen = 0;
        if (!GPQuoteArgument(quotedArg, GP_MAX_PATH, argv[i])) {
            LocalFree(argv);
            return FALSE;
        }
        quotedLen = wcslen(quotedArg);
        if (used + 1 + quotedLen + 1 > destCount) {
            LocalFree(argv);
            return FALSE;
        }
        dest[used++] = L' ';
        wcscpy(dest + used, quotedArg);
        used += quotedLen;
    }

    LocalFree(argv);
    return TRUE;
}

static BOOL GPBuildToolCommandLine(wchar_t *dest,
                                   size_t destCount,
                                   const wchar_t *toolPath,
                                   const wchar_t **args,
                                   int argCount)
{
    int i = 0;
    size_t used = 0;
    wchar_t quotedArg[GP_MAX_PATH];

    if (!GPQuoteArgument(quotedArg, GP_MAX_PATH, toolPath)) {
        return FALSE;
    }

    used = wcslen(quotedArg);
    if (used + 1 > destCount) {
        return FALSE;
    }
    wcscpy(dest, quotedArg);

    for (i = 0; i < argCount; i++) {
      size_t quotedLen = 0;
      if (!GPQuoteArgument(quotedArg, GP_MAX_PATH, args[i])) {
          return FALSE;
      }
      quotedLen = wcslen(quotedArg);
      if (used + 1 + quotedLen + 1 > destCount) {
          return FALSE;
      }
      dest[used++] = L' ';
      wcscpy(dest + used, quotedArg);
      used += quotedLen;
    }

    return TRUE;
}

static BOOL GPRunProcessAndWait(const wchar_t *toolPath,
                                wchar_t *commandLine,
                                const wchar_t *workingDirectory,
                                DWORD creationFlags,
                                DWORD *exitCodeOut)
{
    STARTUPINFOW startupInfo;
    PROCESS_INFORMATION processInfo;
    DWORD exitCode = 1;

    ZeroMemory(&startupInfo, sizeof(startupInfo));
    startupInfo.cb = sizeof(startupInfo);
    startupInfo.dwFlags = STARTF_USESHOWWINDOW;
    startupInfo.wShowWindow = SW_HIDE;
    ZeroMemory(&processInfo, sizeof(processInfo));

    if (!CreateProcessW(toolPath,
                        commandLine,
                        NULL,
                        NULL,
                        FALSE,
                        creationFlags | CREATE_UNICODE_ENVIRONMENT,
                        NULL,
                        workingDirectory,
                        &startupInfo,
                        &processInfo)) {
        return FALSE;
    }

    WaitForSingleObject(processInfo.hProcess, INFINITE);
    if (!GetExitCodeProcess(processInfo.hProcess, &exitCode)) {
        CloseHandle(processInfo.hThread);
        CloseHandle(processInfo.hProcess);
        return FALSE;
    }

    CloseHandle(processInfo.hThread);
    CloseHandle(processInfo.hProcess);
    if (exitCodeOut != NULL) {
        *exitCodeOut = exitCode;
    }
    return TRUE;
}

static BOOL GPSeedAppDefaults(GPLauncherState *state)
{
    wchar_t defaultsPath[GP_MAX_PATH];
    wchar_t commandLine[GP_MAX_PATH];
    DWORD exitCode = 1;
    int i = 0;

    if (state->config.appDefaultsCount == 0) {
        return TRUE;
    }
    if (state->config.appDefaultsDomain[0] == L'\0') {
        GPSetWideValue(state->errorBuffer, GP_MAX_PATH, L"Packaged app defaults were declared without an app defaults domain.");
        return FALSE;
    }
    if (!GPJoinPath(defaultsPath, GP_MAX_PATH, state->runtimeBin, L"defaults.exe")) {
        GPSetWideValue(state->errorBuffer, GP_MAX_PATH, L"Unable to resolve the bundled defaults.exe path.");
        return FALSE;
    }
    if (!GPFileExists(defaultsPath)) {
        swprintf(state->errorBuffer,
                 GP_MAX_PATH,
                 L"Packaged app defaults require defaults.exe at %ls.",
                 defaultsPath);
        return FALSE;
    }

    for (i = 0; i < state->config.appDefaultsCount; i++) {
        const wchar_t *readArgs[3];
        const wchar_t *writeArgs[4];

        readArgs[0] = L"read";
        readArgs[1] = state->config.appDefaultsDomain;
        readArgs[2] = state->config.appDefaults[i].key;
        if (!GPBuildToolCommandLine(commandLine, GP_MAX_PATH, defaultsPath, readArgs, 3) ||
            !GPRunProcessAndWait(defaultsPath, commandLine, state->installRoot, CREATE_NO_WINDOW, &exitCode)) {
            swprintf(state->errorBuffer,
                     GP_MAX_PATH,
                     L"Unable to read packaged app default %ls in domain %ls.",
                     state->config.appDefaults[i].key,
                     state->config.appDefaultsDomain);
            return FALSE;
        }
        if (exitCode == 0) {
            continue;
        }

        writeArgs[0] = L"write";
        writeArgs[1] = state->config.appDefaultsDomain;
        writeArgs[2] = state->config.appDefaults[i].key;
        writeArgs[3] = state->config.appDefaults[i].value;
        if (!GPBuildToolCommandLine(commandLine, GP_MAX_PATH, defaultsPath, writeArgs, 4) ||
            !GPRunProcessAndWait(defaultsPath, commandLine, state->installRoot, CREATE_NO_WINDOW, &exitCode) ||
            exitCode != 0) {
            swprintf(state->errorBuffer,
                     GP_MAX_PATH,
                     L"Unable to seed packaged app default %ls in domain %ls.",
                     state->config.appDefaults[i].key,
                     state->config.appDefaultsDomain);
            return FALSE;
        }
    }

    return TRUE;
}

static BOOL GPApplyEnvironment(const GPLauncherConfig *config,
                               const wchar_t *installRoot,
                               const wchar_t *appRoot,
                               const wchar_t *runtimeRoot,
                               const wchar_t *metadataRoot)
{
    int i = 0;
    wchar_t expanded[GP_MAX_PATH];

    for (i = 0; i < config->envCount; i++) {
        if (!GPExpandTokens(expanded,
                            GP_MAX_PATH,
                            config->env[i].value,
                            installRoot,
                            appRoot,
                            runtimeRoot,
                            metadataRoot)) {
            return FALSE;
        }
        if (config->env[i].policy == GP_ENV_IF_UNSET &&
            GPEnvironmentVariableExists(config->env[i].key)) {
            continue;
        }
        if (!SetEnvironmentVariableW(config->env[i].key, expanded)) {
            return FALSE;
        }
    }

    return TRUE;
}

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE previous, PWSTR commandLine, int showCommand)
{
    STARTUPINFOW startupInfo;
    PROCESS_INFORMATION processInfo;
    GPLauncherState *state = NULL;
    const wchar_t *displayName = L"GNUstep Launcher";
    DWORD pathLen = 0;
    int exitCode = 1;
    int i = 0;

    (void)instance;
    (void)previous;
    (void)commandLine;
    (void)showCommand;

    state = (GPLauncherState *)HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, sizeof(*state));
    if (state == NULL) {
        GPShowError(displayName, L"Unable to allocate launcher state.");
        return 1;
    }

    pathLen = GetModuleFileNameW(NULL, state->launcherPath, GP_MAX_PATH);
    if (pathLen == 0 || pathLen >= GP_MAX_PATH) {
        GPShowError(displayName, L"Unable to resolve the launcher location.");
        goto cleanup;
    }

    if (!GPSetWideValue(state->configPath, GP_MAX_PATH, state->launcherPath) ||
        !PathRenameExtensionW(state->configPath, L".launcher.ini")) {
        GPShowError(displayName, L"Unable to locate the launcher configuration.");
        goto cleanup;
    }

    if (!GPLoadConfig(state->configPath, &state->config)) {
        GPShowError(displayName, L"Unable to load the launcher configuration.");
        goto cleanup;
    }
    displayName = state->config.displayName;

    if (!GPSetWideValue(state->installRoot, GP_MAX_PATH, state->launcherPath) ||
        !PathRemoveFileSpecW(state->installRoot)) {
        GPShowError(displayName, L"Unable to determine the installation directory.");
        goto cleanup;
    }

    if (!GPResolvePathSpec(state->appRoot, GP_MAX_PATH, state->installRoot, state->config.appRootRelative) ||
        !GPResolvePathSpec(state->metadataRoot, GP_MAX_PATH, state->installRoot, state->config.metadataRootRelative) ||
        !GPResolvePathSpec(state->localRuntimeRoot, GP_MAX_PATH, state->installRoot, state->config.runtimeRootRelative) ||
        !GPJoinPath(state->localRuntimeBin, GP_MAX_PATH, state->localRuntimeRoot, L"bin") ||
        !GPResolvePathSpec(state->appPath, GP_MAX_PATH, state->installRoot, state->config.entryRelativePath) ||
        !GPResolvePathSpec(state->workingDirectory, GP_MAX_PATH, state->installRoot, state->config.workingDirectoryRelative)) {
        GPShowError(displayName, L"Unable to resolve package paths.");
        goto cleanup;
    }

    if (!GPFileExists(state->appPath)) {
        GPShowError(displayName, L"The packaged application executable was not found.");
        goto cleanup;
    }

    if (GPDirectoryExists(state->localRuntimeBin)) {
        GPSetWideValue(state->runtimeRoot, GP_MAX_PATH, state->localRuntimeRoot);
        GPSetWideValue(state->runtimeBin, GP_MAX_PATH, state->localRuntimeBin);
    } else if (state->config.fallbackRuntimeRoot[0] != L'\0') {
        wchar_t fallbackBin[GP_MAX_PATH];
        if (!GPJoinPath(fallbackBin, GP_MAX_PATH, state->config.fallbackRuntimeRoot, L"bin")) {
            GPShowError(displayName, L"Unable to construct the fallback runtime path.");
            goto cleanup;
        }
        if (GPDirectoryExists(fallbackBin)) {
            GPSetWideValue(state->runtimeRoot, GP_MAX_PATH, state->config.fallbackRuntimeRoot);
            GPSetWideValue(state->runtimeBin, GP_MAX_PATH, fallbackBin);
        } else {
            GPShowError(displayName, L"GNUstep runtime files were not found.");
            goto cleanup;
        }
    } else {
        GPShowError(displayName, L"GNUstep runtime files were not found.");
        goto cleanup;
    }

    for (i = 0; i < state->config.pathPrependCount; i++) {
        if (!GPExpandTokens(state->expandedPathSpec,
                            GP_MAX_PATH,
                            state->config.pathPrepend[i],
                            state->installRoot,
                            state->appRoot,
                            state->runtimeRoot,
                            state->metadataRoot) ||
            !GPResolvePathSpec(state->resolvedPathSpec, GP_MAX_PATH, state->installRoot, state->expandedPathSpec) ||
            !GPPrependPath(state->resolvedPathSpec)) {
            GPShowError(displayName, L"Unable to configure the runtime search path.");
            goto cleanup;
        }
    }

    if (!GPApplyEnvironment(&state->config, state->installRoot, state->appRoot, state->runtimeRoot, state->metadataRoot)) {
        GPShowError(displayName, L"Unable to configure the launch environment.");
        goto cleanup;
    }

    if (!GPConfigureFontconfig(state->runtimeRoot)) {
        GPShowError(displayName, L"Unable to configure font runtime paths.");
        goto cleanup;
    }

    if (!GPSeedAppDefaults(state)) {
        GPShowError(displayName, state->errorBuffer);
        goto cleanup;
    }

    if (!GPBuildChildCommandLine(state->commandBuffer, GP_MAX_PATH, state->appPath, &state->config)) {
        GPShowError(displayName, L"Unable to prepare the application command line.");
        goto cleanup;
    }

    ZeroMemory(&startupInfo, sizeof(startupInfo));
    startupInfo.cb = sizeof(startupInfo);
    ZeroMemory(&processInfo, sizeof(processInfo));

    if (!CreateProcessW(state->appPath,
                        state->commandBuffer,
                        NULL,
                        NULL,
                        FALSE,
                        CREATE_UNICODE_ENVIRONMENT,
                        NULL,
                        state->workingDirectory,
                        &startupInfo,
                        &processInfo)) {
        swprintf(state->errorBuffer,
                 GP_MAX_PATH,
                 L"Failed to launch the packaged application.\n\nWindows error code: %lu",
                 GetLastError());
        GPShowError(displayName, state->errorBuffer);
        goto cleanup;
    }

    CloseHandle(processInfo.hThread);
    CloseHandle(processInfo.hProcess);
    exitCode = 0;

cleanup:
    if (state != NULL) {
        HeapFree(GetProcessHeap(), 0, state);
    }
    return exitCode;
}
