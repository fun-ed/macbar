#ifndef APP_AUDIO_RT_H
#define APP_AUDIO_RT_H

#include <CoreAudio/CoreAudio.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#pragma clang assume_nonnull begin

typedef struct MBAppAudioRT MBAppAudioRT;

// Validates the complete aggregate layout before the IOProc can be started.
MBAppAudioRT * _Nullable MBAppAudioRTCreate(AudioObjectID aggregate, AudioObjectID physical,
                                AudioStreamBasicDescription tapFormat, OSStatus *status);
void MBAppAudioRTDestroy(MBAppAudioRT *context);
void MBAppAudioRTSetGain(MBAppAudioRT *context, float gain);
void MBAppAudioRTSetEnabled(MBAppAudioRT *context, int enabled);
uint64_t MBAppAudioRTCallbacks(MBAppAudioRT *context);
uint64_t MBAppAudioRTSignals(MBAppAudioRT *context);
int MBAppAudioRTFaulted(MBAppAudioRT *context);
OSStatus MBAppAudioRTDisablePhysicalInputs(AudioObjectID aggregate, AudioDeviceIOProcID proc);
OSStatus MBAppAudioRTIOProc(AudioObjectID device, const AudioTimeStamp *now,
                          const AudioBufferList *input, const AudioTimeStamp *inputTime,
                          AudioBufferList *output, const AudioTimeStamp *outputTime, void * _Nullable context);

// The same bounded processing path is callable from unit tests with synthetic buffer lists.
MBAppAudioRT * _Nullable MBAppAudioRTCreateLayout(uint32_t inputOffset, uint32_t inputBuffers,
                                         uint32_t outputChannels, int inputPlanar, int outputPlanar);
// Channel indices are zero-based; mono requires both indices to be zero.
MBAppAudioRT * _Nullable MBAppAudioRTCreateLayoutWithStereoChannels(uint32_t inputOffset, uint32_t inputBuffers,
                                         uint32_t outputChannels, int inputPlanar, int outputPlanar,
                                         uint32_t leftChannel, uint32_t rightChannel);
int32_t MBAppAudioParentPID(int32_t pid);
int MBAppAudioProcessPath(int32_t pid, char *path, uint32_t capacity);

#pragma clang assume_nonnull end

#ifdef __cplusplus
}
#endif
#endif
