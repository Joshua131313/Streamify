import { AppRouter } from './router/AppRouter';
import { AppProvider } from './context/AppContext';
// @ts-ignore
import 'swiper/css';
import { useMouseIdle } from './hooks/utilHooks/useMouseIdle';

function App() {
  useMouseIdle();
  
  return (
    <AppProvider>
      <AppRouter />
    </AppProvider>
  )
}

export default App;
