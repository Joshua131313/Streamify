import { AppRouter } from "./router/AppRouter";
// @ts-ignore
import 'swiper/css';
import { useMouseIdle } from "./hooks/utilHooks/useMouseIdle";
import { usePWA } from "./hooks/utilHooks/usePWA";
import { AuthProvider } from "./context/AuthContext";

function App() {
  useMouseIdle();
  usePWA();

  return (
      <AppRouter />
  )
}

export default App;