import type { ImgHTMLAttributes } from "react";
import { ImgProxy } from "./ImgProxy";

export type AppImgProps = ImgHTMLAttributes<HTMLImageElement> & {
  skeletonClass?: string;
};

export const AppImg = ({
  src,
  skeletonClass,
  ...props
}: AppImgProps) => {
  return (
    <ImgProxy
      src={src}
      skeletonClass={skeletonClass}
      {...props}
    />
  );
};