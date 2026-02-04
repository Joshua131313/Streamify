import { AppRouter } from './router/AppRouter';
import { AppProvider } from './context/AppContext';
// @ts-ignore
import 'swiper/css';
import { useMouseIdle } from './hooks/utilHooks/useMouseIdle';
import { useScrollToTop } from './hooks/utilHooks/useScrollToTop';

function App() {
  useMouseIdle();
  
  return (
    <AppProvider>
      <AppRouter />
    </AppProvider>
  )
}

export default App;
