#include "AppAudioRT.h"
#include <stdatomic.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <libproc.h>

#define MB_MAX_BUFFERS 32
#define MB_MAX_FRAMES 16384
#define MB_FORMAT_ERROR kAudioDeviceUnsupportedFormatError

struct MBAppAudioRT {
    uint32_t inputOffset;
    uint32_t inputBuffers;
    uint32_t outputChannels;
    uint32_t leftChannel;
    uint32_t rightChannel;
    int inputPlanar;
    int outputPlanar;
    _Atomic(uint32_t) gainBits;
    _Atomic(int) enabled;
    _Atomic(int) fault;
    _Atomic(uint64_t) callbacks;
    _Atomic(uint64_t) signals;
};

static AudioObjectPropertyAddress address(AudioObjectPropertySelector selector, AudioObjectPropertyScope scope) {
    AudioObjectPropertyAddress value = { selector, scope, kAudioObjectPropertyElementMain };
    return value;
}

static OSStatus streams(AudioObjectID device, AudioObjectPropertyScope scope, AudioObjectID *ids, uint32_t *count) {
    AudioObjectPropertyAddress a = address(kAudioDevicePropertyStreams, scope);
    UInt32 size = MB_MAX_BUFFERS * sizeof(AudioObjectID);
    OSStatus status = AudioObjectGetPropertyData(device, &a, 0, NULL, &size, ids);
    if (status) return status;
    if (size > MB_MAX_BUFFERS * sizeof(AudioObjectID) || size % sizeof(AudioObjectID)) return MB_FORMAT_ERROR;
    *count = size / sizeof(AudioObjectID);
    return noErr;
}

static OSStatus format(AudioObjectID stream, AudioStreamBasicDescription *value) {
    AudioObjectPropertyAddress a = address(kAudioStreamPropertyVirtualFormat, kAudioObjectPropertyScopeGlobal);
    UInt32 size = sizeof(*value);
    OSStatus status = AudioObjectGetPropertyData(stream, &a, 0, NULL, &size, value);
    return status ? status : (size == sizeof(*value) ? noErr : MB_FORMAT_ERROR);
}

static int float32(AudioStreamBasicDescription f) {
    uint32_t channelsPerBuffer = (f.mFormatFlags & kAudioFormatFlagIsNonInterleaved) ? 1 : f.mChannelsPerFrame;
    return f.mFormatID == kAudioFormatLinearPCM && (f.mFormatFlags & kAudioFormatFlagIsFloat) &&
        (f.mFormatFlags & kAudioFormatFlagIsPacked) && !(f.mFormatFlags & kAudioFormatFlagIsBigEndian) &&
        f.mBitsPerChannel == 32 && f.mFramesPerPacket == 1 && f.mSampleRate > 0 && isfinite(f.mSampleRate) &&
        f.mChannelsPerFrame > 0 && f.mChannelsPerFrame <= MB_MAX_BUFFERS &&
        f.mBytesPerFrame == channelsPerBuffer * sizeof(float) && f.mBytesPerPacket == f.mBytesPerFrame;
}

static OSStatus startingChannel(AudioObjectID stream, uint32_t *channel) {
    AudioObjectPropertyAddress a = address(kAudioStreamPropertyStartingChannel, kAudioObjectPropertyScopeGlobal);
    UInt32 size = sizeof(*channel);
    OSStatus status = AudioObjectGetPropertyData(stream, &a, 0, NULL, &size, channel);
    return status ? status : (size == sizeof(*channel) && *channel > 0 ? noErr : MB_FORMAT_ERROR);
}

static int sameFormat(AudioStreamBasicDescription a, AudioStreamBasicDescription b) {
    return a.mSampleRate == b.mSampleRate && a.mFormatID == b.mFormatID &&
        a.mFormatFlags == b.mFormatFlags && a.mBytesPerPacket == b.mBytesPerPacket &&
        a.mFramesPerPacket == b.mFramesPerPacket && a.mBytesPerFrame == b.mBytesPerFrame &&
        a.mChannelsPerFrame == b.mChannelsPerFrame && a.mBitsPerChannel == b.mBitsPerChannel;
}

static OSStatus cfProperty(AudioObjectID object, AudioObjectPropertySelector selector, CFTypeRef *value) {
    AudioObjectPropertyAddress a = address(selector, kAudioObjectPropertyScopeGlobal);
    UInt32 size = sizeof(*value);
    OSStatus status = AudioObjectGetPropertyData(object, &a, 0, NULL, &size, value);
    return status ? status : (size == sizeof(*value) && *value ? noErr : MB_FORMAT_ERROR);
}

static OSStatus topology(AudioObjectID aggregate, AudioObjectID physical) {
    AudioObjectID ids[MB_MAX_BUFFERS];
    AudioObjectPropertyAddress a = address(kAudioAggregateDevicePropertyActiveSubDeviceList, kAudioObjectPropertyScopeGlobal);
    UInt32 size = sizeof(ids);
    OSStatus status = AudioObjectGetPropertyData(aggregate, &a, 0, NULL, &size, ids);
    if (status) return status;
    if (size != sizeof(AudioObjectID) || ids[0] != physical || physical == kAudioObjectUnknown) return MB_FORMAT_ERROR;
    a = address(kAudioAggregateDevicePropertySubTapList, kAudioObjectPropertyScopeGlobal);
    size = sizeof(ids);
    status = AudioObjectGetPropertyData(aggregate, &a, 0, NULL, &size, ids);
    if (status) return status;
    if (size != sizeof(AudioObjectID) || ids[0] == kAudioObjectUnknown) return MB_FORMAT_ERROR;

    CFTypeRef full = NULL, uid = NULL, taps = NULL;
    if ((status = cfProperty(aggregate, kAudioAggregateDevicePropertyFullSubDeviceList, &full)) ||
        (status = cfProperty(physical, kAudioDevicePropertyDeviceUID, &uid)) ||
        (status = cfProperty(aggregate, kAudioAggregateDevicePropertyTapList, &taps))) goto done;
    status = MB_FORMAT_ERROR;
    // SDK FullSubDeviceList order defines stream order, not inherited stream IDs.
    if (CFGetTypeID(full) != CFArrayGetTypeID() || CFGetTypeID(uid) != CFStringGetTypeID() ||
        CFGetTypeID(taps) != CFArrayGetTypeID() || CFArrayGetCount(full) != 1 ||
        CFArrayGetCount(taps) != 1) goto done;
    CFTypeRef first = CFArrayGetValueAtIndex(full, 0), tap = CFArrayGetValueAtIndex(taps, 0);
    if (!first || CFGetTypeID(first) != CFStringGetTypeID() || !CFEqual(first, uid) ||
        !tap || CFGetTypeID(tap) != CFStringGetTypeID() || CFStringGetLength(tap) == 0) goto done;
    status = noErr;
done:
    if (full) CFRelease(full);
    if (uid) CFRelease(uid);
    if (taps) CFRelease(taps);
    return status;
}

// Configuration buffers have NULL data. Read into fixed-capacity, properly aligned storage.
static OSStatus configuration(AudioObjectID device, AudioObjectPropertyScope scope,
                              uint32_t *channels, uint32_t *count) {
    union {
        AudioBufferList alignment;
        unsigned char bytes[offsetof(AudioBufferList, mBuffers) + MB_MAX_BUFFERS * sizeof(AudioBuffer)];
    } storage;
    AudioObjectPropertyAddress a = address(kAudioDevicePropertyStreamConfiguration, scope);
    UInt32 size = sizeof(storage);
    OSStatus status = AudioObjectGetPropertyData(device, &a, 0, NULL, &size, &storage);
    if (status) return status;
    AudioBufferList *list = (AudioBufferList *)&storage;
    if (size < offsetof(AudioBufferList, mBuffers) || list->mNumberBuffers > MB_MAX_BUFFERS ||
        size < offsetof(AudioBufferList, mBuffers) + list->mNumberBuffers * sizeof(AudioBuffer)) return MB_FORMAT_ERROR;
    *count = list->mNumberBuffers;
    for (uint32_t i = 0; i < *count; ++i) channels[i] = list->mBuffers[i].mNumberChannels;
    return noErr;
}

MBAppAudioRT *MBAppAudioRTCreateLayout(uint32_t offset, uint32_t inputBuffers,
                                         uint32_t outputChannels, int inputPlanar, int outputPlanar) {
    return MBAppAudioRTCreateLayoutWithStereoChannels(offset, inputBuffers, outputChannels,
                                                     inputPlanar, outputPlanar, 0, outputChannels > 1 ? 1 : 0);
}

MBAppAudioRT *MBAppAudioRTCreateLayoutWithStereoChannels(uint32_t offset, uint32_t inputBuffers,
                                         uint32_t outputChannels, int inputPlanar, int outputPlanar,
                                         uint32_t leftChannel, uint32_t rightChannel) {
    if (inputBuffers != (inputPlanar ? 2 : 1) || offset > MB_MAX_BUFFERS - inputBuffers ||
        outputChannels < 1 || outputChannels > MB_MAX_BUFFERS ||
        leftChannel >= outputChannels || rightChannel >= outputChannels ||
        (outputChannels > 1 && leftChannel == rightChannel)) return NULL;
    MBAppAudioRT *rt = calloc(1, sizeof(*rt));
    if (!rt) return NULL;
    rt->inputOffset = offset;
    rt->inputBuffers = inputBuffers;
    rt->outputChannels = outputChannels;
    rt->leftChannel = leftChannel;
    rt->rightChannel = rightChannel;
    rt->inputPlanar = inputPlanar != 0;
    rt->outputPlanar = outputPlanar != 0;
    atomic_init(&rt->gainBits, 0);
    atomic_init(&rt->enabled, 0);
    atomic_init(&rt->fault, 0);
    atomic_init(&rt->callbacks, 0);
    atomic_init(&rt->signals, 0);
    if (!atomic_is_lock_free(&rt->gainBits) || !atomic_is_lock_free(&rt->enabled) ||
        !atomic_is_lock_free(&rt->fault) || !atomic_is_lock_free(&rt->callbacks) ||
        !atomic_is_lock_free(&rt->signals)) {
        free(rt);
        return NULL;
    }
    return rt;
}

MBAppAudioRT *MBAppAudioRTCreate(AudioObjectID aggregate, AudioObjectID physical,
                                AudioStreamBasicDescription tapFormat, OSStatus *status) {
    AudioObjectID inputIDs[MB_MAX_BUFFERS], physicalIDs[MB_MAX_BUFFERS], outputIDs[MB_MAX_BUFFERS], physicalOutputIDs[MB_MAX_BUFFERS];
    uint32_t inputCount = 0, physicalCount = 0, outputCount = 0, physicalOutputCount = 0;
    uint32_t inputs[MB_MAX_BUFFERS], physicalInputs[MB_MAX_BUFFERS], outputs[MB_MAX_BUFFERS], physicalOutputs[MB_MAX_BUFFERS];
    uint32_t inputBuffers = 0, physicalBuffers = 0, outputBuffers = 0, physicalOutputBuffers = 0;
    AudioStreamBasicDescription inputFormat, outputFormat, physicalFormat;
    *status = MB_FORMAT_ERROR;
    if (!float32(tapFormat) || tapFormat.mChannelsPerFrame != 2) return NULL;
    if ((*status = topology(aggregate, physical)) ||
        (*status = streams(aggregate, kAudioObjectPropertyScopeInput, inputIDs, &inputCount)) ||
        (*status = streams(physical, kAudioObjectPropertyScopeInput, physicalIDs, &physicalCount)) ||
        (*status = streams(aggregate, kAudioObjectPropertyScopeOutput, outputIDs, &outputCount)) ||
        (*status = streams(physical, kAudioObjectPropertyScopeOutput, physicalOutputIDs, &physicalOutputCount))) return NULL;
    *status = MB_FORMAT_ERROR;
    // One physical output stream, cloned physical input prefix, one appended stereo tap.
    if (inputCount != physicalCount + 1 || outputCount != 1 || physicalOutputCount != 1) return NULL;
    uint32_t nextChannel = 1, aggregateStart = 0, physicalStart = 0;
    for (uint32_t i = 0; i < physicalCount; ++i) {
        if ((*status = format(inputIDs[i], &inputFormat)) ||
            (*status = format(physicalIDs[i], &physicalFormat)) ||
            (*status = startingChannel(inputIDs[i], &aggregateStart)) ||
            (*status = startingChannel(physicalIDs[i], &physicalStart))) return NULL;
        *status = MB_FORMAT_ERROR;
        if (!sameFormat(inputFormat, physicalFormat) || aggregateStart != physicalStart ||
            physicalStart != nextChannel || !physicalFormat.mChannelsPerFrame ||
            physicalFormat.mChannelsPerFrame > UINT32_MAX - nextChannel) return NULL;
        nextChannel += physicalFormat.mChannelsPerFrame;
    }
    if ((*status = format(inputIDs[inputCount - 1], &inputFormat)) ||
        (*status = startingChannel(inputIDs[inputCount - 1], &aggregateStart))) return NULL;
    *status = MB_FORMAT_ERROR;
    if (!sameFormat(inputFormat, tapFormat) || aggregateStart < nextChannel) return NULL;
    if ((*status = format(outputIDs[0], &outputFormat)) ||
        (*status = format(physicalOutputIDs[0], &physicalFormat)) ||
        (*status = startingChannel(outputIDs[0], &aggregateStart)) ||
        (*status = startingChannel(physicalOutputIDs[0], &physicalStart))) return NULL;
    *status = MB_FORMAT_ERROR;
    if (!float32(outputFormat) || !sameFormat(outputFormat, physicalFormat) ||
        aggregateStart != 1 || physicalStart != 1 || inputFormat.mSampleRate != outputFormat.mSampleRate) return NULL;
    uint32_t leftChannel = 0, rightChannel = outputFormat.mChannelsPerFrame > 1 ? 1 : 0;
    if (outputFormat.mChannelsPerFrame > 1) {
        AudioObjectPropertyAddress stereo = address(kAudioDevicePropertyPreferredChannelsForStereo, kAudioObjectPropertyScopeOutput);
        if (AudioObjectHasProperty(physical, &stereo)) {
            UInt32 channels[2] = {0, 0}, size = sizeof(channels);
            if ((*status = AudioObjectGetPropertyData(physical, &stereo, 0, NULL, &size, channels))) return NULL;
            *status = MB_FORMAT_ERROR;
            if (size != sizeof(channels) || !channels[0] || !channels[1] ||
                channels[0] > outputFormat.mChannelsPerFrame || channels[1] > outputFormat.mChannelsPerFrame ||
                channels[0] == channels[1]) return NULL;
            leftChannel = channels[0] - 1;
            rightChannel = channels[1] - 1;
        }
    }
    if ((*status = configuration(aggregate, kAudioObjectPropertyScopeInput, inputs, &inputBuffers)) ||
        (*status = configuration(physical, kAudioObjectPropertyScopeInput, physicalInputs, &physicalBuffers)) ||
        (*status = configuration(aggregate, kAudioObjectPropertyScopeOutput, outputs, &outputBuffers)) ||
        (*status = configuration(physical, kAudioObjectPropertyScopeOutput, physicalOutputs, &physicalOutputBuffers))) return NULL;
    *status = MB_FORMAT_ERROR;
    int inputPlanar = (inputFormat.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0;
    int outputPlanar = (outputFormat.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0;
    uint32_t tapBuffers = inputPlanar ? 2 : 1, physicalChannels = 0;
    if (inputBuffers != physicalBuffers + tapBuffers || outputBuffers != physicalOutputBuffers ||
        outputBuffers != (outputPlanar ? outputFormat.mChannelsPerFrame : 1)) return NULL;
    for (uint32_t i = 0; i < physicalBuffers; ++i) {
        if (inputs[i] != physicalInputs[i] || !physicalInputs[i] || physicalInputs[i] > UINT32_MAX - physicalChannels) return NULL;
        physicalChannels += physicalInputs[i];
    }
    if (physicalChannels != nextChannel - 1) return NULL;
    for (uint32_t i = physicalBuffers; i < inputBuffers; ++i) if (inputs[i] != (inputPlanar ? 1 : 2)) return NULL;
    for (uint32_t i = 0; i < outputBuffers; ++i)
        if (outputs[i] != physicalOutputs[i] || outputs[i] != (outputPlanar ? 1 : outputFormat.mChannelsPerFrame)) return NULL;
    // BufferList offsets follow the validated physical buffer prefix, not logical StartingChannel gaps.
    MBAppAudioRT *rt = MBAppAudioRTCreateLayoutWithStereoChannels(physicalBuffers, tapBuffers, outputFormat.mChannelsPerFrame,
                                                               inputPlanar, outputPlanar, leftChannel, rightChannel);
    *status = rt ? noErr : MB_FORMAT_ERROR;
    return rt;
}

OSStatus MBAppAudioRTDisablePhysicalInputs(AudioObjectID aggregate, AudioDeviceIOProcID proc) {
    AudioObjectID ids[MB_MAX_BUFFERS];
    uint32_t count = 0;
    OSStatus status = streams(aggregate, kAudioObjectPropertyScopeInput, ids, &count);
    if (status) return status;
    if (!count || count > MB_MAX_BUFFERS) return MB_FORMAT_ERROR;
    union {
        AudioHardwareIOProcStreamUsage alignment;
        unsigned char bytes[offsetof(AudioHardwareIOProcStreamUsage, mStreamIsOn) + MB_MAX_BUFFERS * sizeof(UInt32)];
    } storage = {0};
    AudioHardwareIOProcStreamUsage *usage = (AudioHardwareIOProcStreamUsage *)&storage;
    usage->mIOProc = (void *)proc;
    usage->mNumberStreams = count;
    usage->mStreamIsOn[count - 1] = 1; // Never enable any physical microphone input stream.
    AudioObjectPropertyAddress a = address(kAudioDevicePropertyIOProcStreamUsage, kAudioObjectPropertyScopeInput);
    UInt32 size = (UInt32)(offsetof(AudioHardwareIOProcStreamUsage, mStreamIsOn) + count * sizeof(UInt32));
    status = AudioObjectSetPropertyData(aggregate, &a, 0, NULL, size, usage);
    if (status) return status;
    memset(&storage, 0, sizeof(storage));
    usage->mIOProc = (void *)proc;
    status = AudioObjectGetPropertyData(aggregate, &a, 0, NULL, &size, usage);
    if (status) return status;
    if (usage->mNumberStreams != count || size < offsetof(AudioHardwareIOProcStreamUsage, mStreamIsOn) + count * sizeof(UInt32)) return MB_FORMAT_ERROR;
    for (uint32_t i = 0; i < count; ++i) if ((usage->mStreamIsOn[i] != 0) != (i == count - 1)) return MB_FORMAT_ERROR;
    return noErr;
}

void MBAppAudioRTDestroy(MBAppAudioRT *rt) { free(rt); }
void MBAppAudioRTSetGain(MBAppAudioRT *rt, float gain) {
    if (!isfinite(gain)) gain = 0;
    gain = fminf(1, fmaxf(0, gain));
    uint32_t bits;
    memcpy(&bits, &gain, sizeof(bits));
    atomic_store_explicit(&rt->gainBits, bits, memory_order_relaxed);
}
void MBAppAudioRTSetEnabled(MBAppAudioRT *rt, int enabled) { atomic_store_explicit(&rt->enabled, enabled != 0, memory_order_relaxed); }
uint64_t MBAppAudioRTCallbacks(MBAppAudioRT *rt) { return atomic_load_explicit(&rt->callbacks, memory_order_relaxed); }
uint64_t MBAppAudioRTSignals(MBAppAudioRT *rt) { return atomic_load_explicit(&rt->signals, memory_order_relaxed); }
int MBAppAudioRTFaulted(MBAppAudioRT *rt) { return atomic_load_explicit(&rt->fault, memory_order_relaxed); }

static uint32_t frames(const AudioBuffer *buffer, uint32_t channels) {
    if (buffer->mNumberChannels != channels || !buffer->mData ||
        (uintptr_t)buffer->mData % _Alignof(float) || buffer->mDataByteSize % (channels * sizeof(float))) return 0;
    uint32_t count = buffer->mDataByteSize / (channels * sizeof(float));
    return count <= MB_MAX_FRAMES ? count : 0;
}

OSStatus MBAppAudioRTIOProc(AudioObjectID device, const AudioTimeStamp *now,
                          const AudioBufferList *input, const AudioTimeStamp *inputTime,
                          AudioBufferList *output, const AudioTimeStamp *outputTime, void *context) {
    (void)device; (void)now; (void)inputTime; (void)outputTime;
    MBAppAudioRT *rt = context;
    if (!rt) return noErr;
    atomic_fetch_add_explicit(&rt->callbacks, 1, memory_order_relaxed);
    if (!input || !output || input->mNumberBuffers != rt->inputOffset + rt->inputBuffers ||
        output->mNumberBuffers != (rt->outputPlanar ? rt->outputChannels : 1)) goto fault;
    // HAL may retain allocated disabled physical input buffers; never inspect their pointers or contents.
    const AudioBuffer *left = &input->mBuffers[rt->inputOffset];
    const AudioBuffer *right = rt->inputPlanar ? &input->mBuffers[rt->inputOffset + 1] : left;
    uint32_t count = frames(left, rt->inputPlanar ? 1 : 2);
    if (!count || frames(right, rt->inputPlanar ? 1 : 2) != count) goto fault;
    for (uint32_t i = 0; i < output->mNumberBuffers; ++i)
        if (frames(&output->mBuffers[i], rt->outputPlanar ? 1 : rt->outputChannels) != count) goto fault;
    uint32_t bits = atomic_load_explicit(&rt->gainBits, memory_order_relaxed);
    float gain;
    memcpy(&gain, &bits, sizeof(gain));
    if (!atomic_load_explicit(&rt->enabled, memory_order_relaxed) || atomic_load_explicit(&rt->fault, memory_order_relaxed)) gain = 0;
    int signal = 0;
    const float *l = left->mData, *r = right->mData;
    for (uint32_t frame = 0; frame < count; ++frame) {
        float lv = l[frame * (rt->inputPlanar ? 1 : 2)];
        float rv = r[frame * (rt->inputPlanar ? 1 : 2) + (rt->inputPlanar ? 0 : 1)];
        if (!isfinite(lv) || !isfinite(rv)) goto fault;
        if (fabsf(lv) > 0.0000001f || fabsf(rv) > 0.0000001f) signal = 1;
        for (uint32_t channel = 0; channel < rt->outputChannels; ++channel) {
            AudioBuffer *buffer = &output->mBuffers[rt->outputPlanar ? channel : 0];
            float *destination = buffer->mData;
            float value = rt->outputChannels == 1 ? lv * 0.5f + rv * 0.5f :
                (channel == rt->leftChannel ? lv : (channel == rt->rightChannel ? rv : 0));
            destination[frame * (rt->outputPlanar ? 1 : rt->outputChannels) + (rt->outputPlanar ? 0 : channel)] = value * gain;
        }
    }
    if (signal) atomic_fetch_add_explicit(&rt->signals, 1, memory_order_relaxed);
    return noErr;
fault:
    atomic_store_explicit(&rt->fault, 1, memory_order_relaxed);
    // HAL zeroes output on entry; clear any partial write after a non-finite sample.
    if (output && output->mNumberBuffers <= MB_MAX_BUFFERS)
        for (uint32_t i = 0; i < output->mNumberBuffers; ++i)
            if (output->mBuffers[i].mData &&
                output->mBuffers[i].mDataByteSize <= MB_MAX_FRAMES * (rt->outputPlanar ? 1 : rt->outputChannels) * sizeof(float))
                memset(output->mBuffers[i].mData, 0, output->mBuffers[i].mDataByteSize);
    return noErr;
}

int32_t MBAppAudioParentPID(int32_t pid) {
    struct proc_bsdinfo info = {0};
    return proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, sizeof(info)) == sizeof(info) ? (int32_t)info.pbi_ppid : 0;
}
int MBAppAudioProcessPath(int32_t pid, char *path, uint32_t capacity) {
    return proc_pidpath(pid, path, capacity);
}
