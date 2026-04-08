import { useEffect, useState } from "react";

export const usePWA = () => {
  const [isPWA, setIsPWA] = useState(false);

  useEffect(() => {
    const checkPWA = () => {
      const standaloneMatch = window.matchMedia('(display-mode: standalone)').matches;
      const iosStandalone = (window.navigator as any).standalone === true;

      return standaloneMatch || iosStandalone;
    };

    const update = () => {
      const result = checkPWA();
      setIsPWA(result);
      document.body.classList.toggle('pwa', result);
    };

    update();

    const media = window.matchMedia('(display-mode: standalone)');
    media.addEventListener('change', update);

    return () => {
      media.removeEventListener('change', update);
      document.body.classList.remove('pwa');
    };
  }, []);

  return isPWA;
};