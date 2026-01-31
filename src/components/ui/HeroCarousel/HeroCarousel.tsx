import { useHeroMedia } from "../../../hooks/mediaHooks/useHeroMedia"
import "./HeroCarousel.css"
import { Swiper, SwiperSlide } from "swiper/react";
import { HeroSlide } from "./HeroSlide";
import { Autoplay } from "swiper/modules";


export const HeroCarousel = () => {
    const [heroes, loading] = useHeroMedia();
    console.log("heroes", heroes)
    const carouselSlides = heroes.map(hero => {
        return (
            <SwiperSlide>
                 <HeroSlide key={hero.id} media={hero}/>
            </SwiperSlide>
        )
    })
    return (
        <Swiper 
            slidesPerView={1}
            autoplay={{
                delay: 8000,
            }}
            modules={[Autoplay]}
            className="hero-carousel"
        >
           {carouselSlides}
        </Swiper>
    )
}