import type { ImgHTMLAttributes } from "react";
import type { TMDBImageSize, TMDBImageType } from "../../../types/tmdb";
import { getTMDBImageUrl } from "../../../utils/getTMDBImageUrl";
import { ImgProxy } from "./ImgProxy";

export type TMDBImgProps<T extends TMDBImageType> =
  Omit<ImgHTMLAttributes<HTMLImageElement>, "src"> & {
    type: T;
    path?: string | null;
    size?: TMDBImageSize<T>;
    skeletonClass?: string;
  };

export const TMDBImg = <T extends TMDBImageType>({
  type,
  path,
  size,
  skeletonClass,
  ...props
}: TMDBImgProps<T>) => {
  const src = getTMDBImageUrl(type, path ?? "", size);

  return (
    <ImgProxy
      src={src || null}
      skeletonClass={skeletonClass}
      {...props}
    />
  );
};