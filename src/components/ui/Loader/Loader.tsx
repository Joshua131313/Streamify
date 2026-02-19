// src/components/ui/Loader/Loader.tsx
import "./Loader.css";

interface Props {
  fullScreen?: boolean;
  text?: string;
  showLogo?: boolean;
}

export const Loader = ({ fullScreen = false, showLogo = true, text }: Props) => {
  return (
    <div className={`loader ${fullScreen ? "fullscreen" : ""}`}>
        {fullScreen && showLogo && <div className="logo">Streamify</div>}
        <div className="spinner" />
        {text && <p className="loader-text">{text}</p>}
    </div>
  );
};
