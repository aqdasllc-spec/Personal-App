package app.folio.folio

// local_auth (biometric app lock) needs a FragmentActivity on Android; audio_service (lock-screen controls for
// "Listen") needs its own variant of it so both can share the app's engine.
import com.ryanheise.audioservice.AudioServiceFragmentActivity

class MainActivity : AudioServiceFragmentActivity()
