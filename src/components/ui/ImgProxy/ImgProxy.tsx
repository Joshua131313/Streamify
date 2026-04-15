import { useState, type ImgHTMLAttributes } from "react";
import "./ImgProxy.css";

export interface ImgProxyProps
  extends Omit<ImgHTMLAttributes<HTMLImageElement>, "src"> {
  src?: string | null;
  skeletonClass?: string;
}

export const ImgProxy = ({
  src,
  skeletonClass,
  onLoad,
  style,
  ...imgProps
}: ImgProxyProps) => {
  const [isLoading, setIsLoading] = useState(true);

  const handleLoad: React.ReactEventHandler<HTMLImageElement> = (e) => {
    setIsLoading(false);
    onLoad?.(e);
  };

  if (!src) {
    return <div className={`img-skeleton ${skeletonClass ?? ""}`} />;
  }

  return (
    <>
      <img
        src={src}
        onLoad={handleLoad}
        style={{
          display: isLoading ? "none" : "block",
          ...style,
        }}
        {...imgProps}
      />

      {isLoading && (
        <div className={`img-skeleton ${skeletonClass ?? ""}`} />
      )}
    </>
  );
};