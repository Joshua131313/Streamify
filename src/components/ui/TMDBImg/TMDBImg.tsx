import { useState, type ImgHTMLAttributes } from "react";
import "./TMDBImg.css"

interface Props extends ImgHTMLAttributes<HTMLImageElement> {
    path: string;
    skeletonClass?: string;
}

export const TMDBImg = ({path, skeletonClass, ...imgProps} : Props) => {
    const [isLoading, setIsLoading] = useState(true);
    
    return (
        <>
            <img  
                style={{
                    display: isLoading ? "none" : "block"
                }}
                onLoad={() => setIsLoading(false)}
                src={`https://image.tmdb.org/t/p/original${path}`} 
                {...imgProps}
            />
            <div 
                style={{
                    display: isLoading ? "block" : "none"
                }}
                className={`img-skeleton ${skeletonClass}`}
            />
        </>
    )
}