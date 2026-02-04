
import { Swiper, SwiperSlide } from 'swiper/react';
import { Navigation } from 'swiper/modules';


import "./MediaRail.css"
import { useMediaRail } from './MediaRailContext';
import { MediaCard } from '../../ui/MediaCard/MediaCard';
import { Top10MediaCard } from '../../ui/MediaCard/Top10MediaCard';
import { useMediaDiscover } from '../../../hooks/mediaHooks/useMediaDiscover';
import { MediaSkeletonCard } from '../../ui/MediaCard/SkeletonCards/MediaSkeletonCard';

export const MediaRailSwiper = () => {
    const { genre, provider, mediaType, category, variant } = useMediaRail();
    const { media, isLoading } = useMediaDiscover({
        mediaType,
        category,
        genreId: genre,
        provider,
    })
    const swiperSlides = media.map((m, i) => {
        return (
            <SwiperSlide key={m.id}>
                {
                    variant === "top10" ?
                    <Top10MediaCard rank={i + 1} media={m}/>
                    :
                    <MediaCard media={m}/>
                }
            </SwiperSlide>
        )
    })

    const skeletonSlides = Array.from({ length: 5 }).map((_, i) => {
        return (
            <SwiperSlide key={i}>
                <MediaSkeletonCard />
            </SwiperSlide>
        )
    })

    return  (
        <Swiper
            className={`media-swiper ${variant === "top10" && "top-10-media-swiper"}`}
            slidesPerView={"auto"}
            spaceBetween={variant === "top10" ? 100 : 10}
            navigation
            modules={[Navigation]}
        >
            {
                isLoading ?
                    skeletonSlides
                    :
                    swiperSlides
                    
            }
        </Swiper>
    )
}