import { AppRouter } from './router/AppRouter';
import { AppProvider } from './context/AppContext';
// @ts-ignore
import 'swiper/css';
import { useMouseIdle } from './hooks/utilHooks/useMouseIdle';
import { useEffect } from 'react';
import { ContextMenuProvider } from './context/ContextMenu';
import { SportsProvider } from './context/SportsContext';
import { MultiWatch } from './pages/Sports/MultiWatch';
import { MultiWatchProvider } from './context/MultiWatchContext';
import { WindowManagerProvider } from './context/WindowManagerContext';
import { WindowRenderer } from './components/ui/Window/WindowRenderer';
import { AuthProvider } from './context/AuthContext';
import { HelmetProvider } from 'react-helmet-async';
import { WatchHistoryProvider } from './context/WatchHistoryContext';
import { SavedMediaProvider } from './context/SavedMediaContext';
import { SearchHistoryProvider } from './context/SearchHistoryContext';


export const DataProviders = ({ children }: { children: React.ReactNode }) => {
  return (
    <SavedMediaProvider>
      <SearchHistoryProvider>
        <WatchHistoryProvider>
          {children}
        </WatchHistoryProvider>
      </SearchHistoryProvider>
    </SavedMediaProvider>
  );
};

const UIProviders = ({ children }: { children: React.ReactNode }) => {
  return (
    <ContextMenuProvider>
      <WindowManagerProvider>
        <MultiWatchProvider>
          <SportsProvider>
            {children}
          </SportsProvider>
        </MultiWatchProvider>
      </WindowManagerProvider>
    </ContextMenuProvider>
  );
};

function App() {
  useMouseIdle();
  // Add onboarding feature to ask favorite media genre, favorite sports team, 
  return (
    <AuthProvider>
      <HelmetProvider>
        <AppProvider>
          <DataProviders>
            <UIProviders>
              <WindowRenderer />
              <div className="body">
                <AppRouter />
              </div>
            </UIProviders>
          </DataProviders>
        </AppProvider>
      </HelmetProvider>
    </AuthProvider>
  )
}

export default App;
