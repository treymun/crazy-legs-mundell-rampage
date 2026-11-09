"""Offline mono Opus writer using the libopus already shipped with pygame-ce."""
import ctypes as ct
from ctypes.util import find_library
from pathlib import Path
import struct
from zlib import crc32

import numpy as np


INPUT_RATE = 24000
FRAME = INPUT_RATE // 50
OPUS_APPLICATION_AUDIO = 2049
OPUS_SET_BITRATE = 4002
OPUS_GET_LOOKAHEAD = 4027


def crc_table():
    values = []
    for i in range(256):
        value = i << 24
        for _ in range(8):
            value = (value << 1) ^ (0x04C11DB7 if value & 0x80000000 else 0)
        values.append(value & 0xFFFFFFFF)
    return tuple(values)


OGG_CRC = crc_table()


def page(packets, flags, granule, serial, sequence):
    laces = bytes(part for packet in packets
                  for part in (*([255]*(len(packet)//255)),len(packet)%255))
    header = struct.pack("<4sBBQIIIB",b"OggS",0,flags,granule,serial,sequence,0,len(laces))
    block = bytearray(header+laces+b"".join(packets))
    checksum = 0
    for byte in block:
        checksum = ((checksum << 8) & 0xFFFFFFFF) ^ OGG_CRC[(checksum >> 24) ^ byte]
    struct.pack_into("<I",block,22,checksum)
    return block


def libopus():
    import pygame

    dll = Path(pygame.__file__).with_name("libopus-0.dll")
    api = ct.CDLL(str(dll) if dll.is_file() else find_library("opus") or "libopus.so.0")
    api.opus_encoder_create.argtypes = ct.c_int,ct.c_int,ct.c_int,ct.POINTER(ct.c_int)
    api.opus_encoder_create.restype = ct.c_void_p
    api.opus_encoder_destroy.argtypes = ct.c_void_p,
    api.opus_encoder_destroy.restype = None
    api.opus_encoder_ctl.argtypes = ct.c_void_p,ct.c_int
    api.opus_encoder_ctl.restype = ct.c_int
    api.opus_encode_float.argtypes = (ct.c_void_p,ct.POINTER(ct.c_float),ct.c_int,
                                     ct.POINTER(ct.c_ubyte),ct.c_int)
    api.opus_encode_float.restype = ct.c_int
    return api


def write_opus(path, samples, rate):
    api = libopus()
    error = ct.c_int()
    encoder = api.opus_encoder_create(INPUT_RATE,1,OPUS_APPLICATION_AUDIO,ct.byref(error))
    if error.value or not encoder:
        raise RuntimeError(f"libopus encoder failed ({error.value})")
    try:
        lookahead = ct.c_int()
        if (api.opus_encoder_ctl(encoder,OPUS_SET_BITRATE,ct.c_int(48000))
                or api.opus_encoder_ctl(encoder,OPUS_GET_LOOKAHEAD,ct.byref(lookahead))):
            raise RuntimeError("Could not configure libopus")
        n = round(len(samples)*INPUT_RATE/rate)
        pcm = np.interp(np.arange(n)*rate/INPUT_RATE,np.arange(len(samples)),samples).astype(np.float32)
        encoded_end = n+lookahead.value
        pcm = np.pad(pcm,(0,encoded_end-n+(-encoded_end)%FRAME))
        serial = crc32(path.stem.encode("ascii"))
        skip = lookahead.value*48000//INPUT_RATE
        head = b"OpusHead"+struct.pack("<BBHIhB",1,1,skip,INPUT_RATE,0,0)
        vendor = b"Mundell offline sampler"
        tags = b"OpusTags"+struct.pack("<I",len(vendor))+vendor+struct.pack("<I",0)
        buffer = (ct.c_ubyte*1276)()
        with path.open("wb") as output:
            output.write(page([head],2,0,serial,0))
            output.write(page([tags],0,0,serial,1))
            packets,sequence = [],2
            for begin in range(0,len(pcm),FRAME):
                frame = pcm[begin:begin+FRAME].ctypes.data_as(ct.POINTER(ct.c_float))
                size = api.opus_encode_float(encoder,frame,FRAME,buffer,len(buffer))
                if size<=0:
                    raise RuntimeError(f"Opus rejected a frame ({size})")
                packets.append(bytes(buffer[:size]))
                tail = begin+FRAME==len(pcm)
                if len(packets)==35 or tail:
                    granule = min(encoded_end,begin+FRAME)*48000//INPUT_RATE
                    output.write(page(packets,4 if tail else 0,granule,serial,sequence))
                    packets.clear()
                    sequence+=1
        return n/INPUT_RATE
    finally:
        api.opus_encoder_destroy(encoder)
