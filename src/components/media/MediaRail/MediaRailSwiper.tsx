
import { Swiper, SwiperSlide } from 'swiper/react';
import { Navigation } from 'swiper/modules';


import "./MediaRail.css"
import { useMediaRail } from './MediaRailContext';
import { MediaCard } from '../../ui/MediaCard/MediaCard';
import { Top10MediaCard } from '../../ui/MediaCard/Top10MediaCard';
import { useMediaDiscover } from '../../../hooks/mediaHooks/useMediaDiscover';
import { MediaSkeletonCard } from '../../ui/MediaCard/SkeletonCards/MediaSkeletonCard';
import { useRef } from 'react';
import { FaChevronLeft, FaChevronRight } from 'react-icons/fa';

export const MediaRailSwiper = () => {
    const { genre, provider, mediaType, category, variant } = useMediaRail();
    const { media, isLoading } = useMediaDiscover({
        mediaType,
        category,
        genreId: genre,
        provider,
    })

    const prevRef = useRef<HTMLDivElement | null>(null);
    const nextRef = useRef<HTMLDivElement | null>(null);


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
        <div className="swiper-container">
            <div ref={prevRef} className="prev-button swiper-nav-button">
                <FaChevronLeft />
            </div>
            <div ref={nextRef} className="next-button swiper-nav-button">
                <FaChevronRight />
            </div>
            <Swiper
                className={`media-swiper ${variant === "top10" && "top-10-media-swiper"}`}
                slidesPerView={"auto"}
                spaceBetween={variant === "top10" ? 100 : 10}
                navigation
                modules={[Navigation]}
                onBeforeInit={(swiper) => {
                    //@ts-ignore
                    swiper.params.navigation.prevEl = prevRef.current;
                    //@ts-ignore
                    swiper.params.navigation.nextEl = nextRef.current;
                }}
            >
                {
                isLoading ?
                    skeletonSlides
                    :
                    swiperSlides
                }
            </Swiper>
        </div>
    )
}