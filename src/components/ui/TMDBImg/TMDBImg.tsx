import type { ImgHTMLAttributes } from "react";

interface Props extends ImgHTMLAttributes<HTMLImageElement> {
    path: string;
}

export const TMDBImg = ({path, ...imgProps} : Props) => {
    return (
        <img 
            src={`https://image.tmdb.org/t/p/original${path}`} 
            {...imgProps}
        />
    )
}