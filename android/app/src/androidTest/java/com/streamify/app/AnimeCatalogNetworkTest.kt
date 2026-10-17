package com.streamify.app
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.streamify.app.data.AnimeCatalog
import kotlinx.coroutines.runBlocking
import org.junit.Test
import org.junit.Assert.*
import org.junit.runner.RunWith
@RunWith(AndroidJUnit4::class)
class AnimeCatalogNetworkTest {
 @Test fun categoryRequestsAndPagination() = runBlocking {
  val first = AnimeCatalog.catalog(1,"",false)
  assertTrue(first.items.isNotEmpty())
  val second = AnimeCatalog.catalog(2,"",false)
  assertTrue(second.items.isNotEmpty())
  assertNotEquals(first.items.first().id,second.items.first().id)
  assertTrue(AnimeCatalog.catalog(1,"",true,"Action").items.isNotEmpty())
 }
}
