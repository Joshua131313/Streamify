// src/components/ui/Loader/Loader.tsx
import { StaticLogo } from "../Logo/StaticLogo";
import "./Loader.css";

interface Props {
  fullScreen?: boolean;
  text?: string;
  showLogo?: boolean;
}

export const Loader = ({ fullScreen = false, showLogo = true, text }: Props) => {
  return (
    <div className={`loader ${fullScreen ? "fullscreen" : ""}`}>
      {fullScreen && showLogo &&
        <StaticLogo />
      }
      <div className="spinner" />
      {text && <p className="loader-text">{text}</p>}
    </div>
  );
};
