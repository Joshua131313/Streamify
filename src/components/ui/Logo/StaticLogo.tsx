import { AppImg } from "../ImgProxy/AppImg"

export const StaticLogo = () => {

    return (
         <div className="logo">
          <AppImg
            src="/logo/logo.png"
          />
          <span>Streamify</span>
        </div>
    )
}