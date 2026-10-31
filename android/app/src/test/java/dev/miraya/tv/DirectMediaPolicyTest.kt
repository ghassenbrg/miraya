package dev.miraya.tv

import org.junit.Assert.*
import org.junit.Test

class DirectMediaPolicyTest {
    @Test fun onlyHttpsMediaWithoutCredentialsIsAccepted() {
        assertTrue(DirectMediaPolicy.validRemote("https://example.com/video.mp4?token=private"))
        for (address in listOf("file:///etc/passwd", "content://settings/system", "http://example.com/video", "https://user:password@example.com/", "blob:https://example.com/id", "https://")) assertFalse(address, DirectMediaPolicy.validRemote(address))
    }
    @Test fun selectedFileRangesAreBoundedWithoutAdditionOverflow() {
        assertTrue(DirectMediaPolicy.validRead(Long.MAX_VALUE, 1, Long.MAX_VALUE))
        assertFalse(DirectMediaPolicy.validRead(-1, 1, 10)); assertFalse(DirectMediaPolicy.validRead(11, 1, 10))
        assertFalse(DirectMediaPolicy.validRead(0, 32769, 10)); assertFalse(DirectMediaPolicy.validRead(0, 0, 10))
    }
    @Test fun identityMustBeCanonicalUuid() {
        assertTrue(DirectMediaPolicy.validId("93e12991-6f7d-4e8f-9bea-7759c26da299"))
        assertFalse(DirectMediaPolicy.validId("1-1-1-1-1")); assertFalse(DirectMediaPolicy.validId("../../private"))
    }
}
