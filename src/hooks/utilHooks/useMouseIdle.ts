import { useEffect, useRef } from "react";

export function useMouseIdle(delay = 3000) {
  const timeoutRef = useRef<number | null>(null);

  useEffect(() => {
    const handleActivity = () => {
      document.body.classList.remove("idle");

      if (timeoutRef.current) {
        clearTimeout(timeoutRef.current);
      }

      timeoutRef.current = window.setTimeout(() => {
        document.body.classList.add("idle");
      }, delay);
    };

    document.addEventListener("mousemove", handleActivity);

    handleActivity();

    return () => {
      document.removeEventListener("mousemove", handleActivity);
      if (timeoutRef.current) {
        clearTimeout(timeoutRef.current);
      }
      document.body.classList.remove("idle");
    };
  }, [delay]);
}
