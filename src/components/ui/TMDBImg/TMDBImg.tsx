import { useState, type ImgHTMLAttributes } from "react";
import "./TMDBImg.css";
import type { TMDBImageSize, TMDBImageType } from "../../../types/tmdb";
import { getTMDBImageUrl } from "../../../utils/getTMDBImageUrl";


export type TMDBImgProps<T extends TMDBImageType> =
  Omit<ImgHTMLAttributes<HTMLImageElement>, "src"> & {
    type: T;
    path?: string;
    size?: TMDBImageSize<T>;
    skeletonClass?: string;
  };

export const TMDBImg = <T extends TMDBImageType>({
  type,
  path,
  size,
  skeletonClass,
  onLoad,
  style,
  ...imgProps
}: TMDBImgProps<T>) => {
  const src = getTMDBImageUrl(type, path, size);
  const [isLoading, setIsLoading] = useState(true);

  const handleLoad: React.ReactEventHandler<HTMLImageElement> = (e) => {
    setIsLoading(false);
    onLoad?.(e); // preserve external onLoad
  };

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
