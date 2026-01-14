# Cactus OpenAI Server

Turn your Android phone into a high-performance OpenAI-compatible API server using Cactus LLM engine. Get 16-75 tok/s local inference with full /v1/chat/completions endpoint.

## Why This Exists

You probably found this repo because you, like me, realized nobody had built the obvious thing: **a phone-based LLM server with Cactus's ARM-tuned kernels AND OpenAI's API**.

- Cactus gives you 2-10× the speed of generic llama.cpp/Ollama on phones
- OpenAI API lets any tool (n8n, LangChain, etc.) talk to your phone without custom clients
- This repo is the missing piece

## Performance

| Device Type | Expected Speed (Qwen3-0.6B INT8) |
|-------------|----------------------------------|
| Pixel 6a, Galaxy S21, iPhone 11 | 16-20 tok/s |
| Pixel 9, Galaxy S25, iPhone 16 Pro | 50-70 tok/s |
| iPhone 17 Pro (flagships) | 75+ tok/s |

## Setup for Your Two Android Phones

### Prerequisites
- Windows PC with Flutter + Android Studio installed
- Two Android phones on same Wi-Fi
- USB cables for both phones

### Step 1: Install Flutter (One-Time)

```powershell
# Download Flutter SDK from flutter.dev
# Extract to C:\src\flutter
# Add to PATH: C:\src\flutter\bin

# Verify install
flutter doctor

# Install Android Studio if prompted
# Accept Android licenses
flutter doctor --android-licenses
```

### Step 2: Clone & Build

```powershell
git clone https://github.com/AudiTistic/cactus-openai-server.git
cd cactus-openai-server

# Get dependencies
flutter pub get

# Build release APK
flutter build apk --release
```

APK will be in `build/app/outputs/flutter-apk/app-release.apk`

### Step 3: Install on Both Phones

**Option A: USB Install**
```powershell
# Enable Developer Options + USB Debugging on both phones
# Connect Phone 1 via USB
flutter devices  # Verify it shows up
flutter install  # Or: adb install build/app/outputs/flutter-apk/app-release.apk

# Repeat for Phone 2
```

**Option B: File Transfer**
- Copy `app-release.apk` to each phone
- Open file manager, tap APK, install

### Step 4: Run Server on Each Phone

1. Open "Cactus OpenAI Server" app on both phones
2. App displays server URL: `http://192.168.x.x:8080/v1/chat/completions`
3. Tap "Start Server" on each
4. Note each phone's IP (Phone 1: 192.168.1.100, Phone 2: 192.168.1.101, for example)

### Step 5: Test from Your PC

```python
from openai import OpenAI

# Test Phone 1
client1 = OpenAI(
    base_url="http://192.168.1.100:8080/v1",
    api_key="local-key",  # Any value works
)

response = client1.chat.completions.create(
    model="cactus-default",
    messages=[{"role": "user", "content": "Hello from phone 1"}],
    max_tokens=100,
)
print(response.choices[0].message.content)

# Repeat for Phone 2 with its IP
```

### Step 6: Keep Phones Awake

- Disable battery optimization for the app
- Keep phones plugged in
- Set screen timeout to max or use "Stay awake while charging" in Developer Options

## Using with n8n, LangChain, etc.

Any tool that accepts custom OpenAI endpoints works. Just set:
- Base URL: `http://<phone-ip>:8080/v1`
- API Key: any non-empty string
- Model: `cactus-default`

**Example: Load-balance across both phones**
```python
import random
from openai import OpenAI

phones = ["192.168.1.100", "192.168.1.101"]

def get_client():
    ip = random.choice(phones)
    return OpenAI(base_url=f"http://{ip}:8080/v1", api_key="local")

# Now your agents automatically round-robin between phones
client = get_client()
```

## Supported Endpoints

- `POST /v1/chat/completions` - OpenAI chat format
- `GET /v1/models` - List available models
- `GET /` - Health check

## FAQ

**Q: Do I need a Cactus telemetry token?**  
A: Not for basic testing. For production, uncomment the `CactusConfig` line in `main.dart` and add your token.

**Q: Can I use different models?**  
A: Cactus auto-downloads small models on first run. For custom models, see [Cactus docs](https://pub.dev/packages/cactus).

**Q: Why not just use Ollama on Termux?**  
A: Cactus is 2-10× faster on the same hardware due to ARM-specific kernels. If you're okay with ~3 tok/s, Ollama is easier.

**Q: Can I run this on iOS?**  
A: Yes, but you need a Mac to build. Change `flutter build apk` to `flutter build ios` and use Xcode to deploy.

## Contributing

PRs welcome. Focus areas:
- Streaming support (`/v1/chat/completions` with SSE)
- Model selection UI
- Battery optimization profiles

## License

MIT - do whatever you want with this.
