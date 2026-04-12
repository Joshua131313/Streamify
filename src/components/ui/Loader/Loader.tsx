// src/components/ui/Loader/Loader.tsx
import { StaticLogo } from "../Logo/StaticLogo";
import "./Loader.css";

interface Props {
  fullScreen?: boolean;
  text?: string;
  showLogo?: boolean;
  isExiting?: boolean;
  onExitAnimationEnd?: () => void;
}

export const Loader = ({
  fullScreen = false,
  showLogo = true,
  text,
  isExiting = false,
  onExitAnimationEnd,
}: Props) => {
  return (
    <div className={`loader ${fullScreen ? "fullscreen" : ""} ${isExiting ? "loader-exit" : ""}`}>
      {fullScreen && showLogo && (
        <div
          className="loader-logo-wrap"
          onAnimationEnd={isExiting ? onExitAnimationEnd : undefined}
        >
          <StaticLogo />
          {!isExiting && <div className="loader-logo-shine" />}
        </div>
      )}

      {!fullScreen && <div className="spinner" />}
    </div>
  );
};