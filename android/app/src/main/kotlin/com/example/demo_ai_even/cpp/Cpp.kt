package com.example.demo_ai_even.cpp

object Cpp {

    // `System.loadLibrary("lc3")` is intentionally not called here to avoid
    // classloader timing issues during app startup. Load the native library
    // explicitly from the activity before using native methods.

    fun init() {}

    @JvmStatic
    external fun decodeLC3(lc3Data: ByteArray?): ByteArray?
    @JvmStatic
    external fun rnNoise(st:Long, input: FloatArray):FloatArray
    @JvmStatic
    external fun createRNNoiseState():Long
    @JvmStatic
    external fun destroyRNNoiseState(st:Long)
}