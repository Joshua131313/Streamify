import { useHeroMedia } from "../../../hooks/mediaHooks/useHeroMedia"
import "./HeroCarousel.css"
import { Swiper, SwiperSlide } from "swiper/react";
import { HeroSlide } from "./HeroSlide";
import { Autoplay, Virtual } from "swiper/modules";
import { useState } from "react";


export const HeroCarousel = () => {
    const { media: heroes } = useHeroMedia();

    const carouselSlides = heroes.map((hero, i) => {
        return (
            <SwiperSlide virtualIndex={i} key={hero.id}>
                 <HeroSlide key={hero.id} media={hero} />
            </SwiperSlide>
        )
    });
    
    return (
        <Swiper 
            slidesPerView={1}
            autoplay={{
                delay: 8000,
            }}
            virtual
            modules={[Autoplay, Virtual]}
            className="hero-carousel"
        >
           {carouselSlides}
        </Swiper>
    )
}