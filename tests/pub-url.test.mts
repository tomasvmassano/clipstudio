import { parsePostUrl, postUrlProblem } from "../src/lib/pub-url.ts";

let bad = 0; let n = 0;
const eq = (name: string, got: unknown, exp: unknown) => {
  n++; const g = JSON.stringify(got), e = JSON.stringify(exp);
  if (g !== e) { bad++; console.log("FAIL", name, g, "esperado", e); }
};
// Mesmos casos de supabase/tests/w10_publicacao_manual.sql (_pub_post_url)
eq("IG reel com query", parsePostUrl("instagram", "https://www.instagram.com/reel/FXitsnumeiro1/?igsh=abc"),
  { external_id: "FXitsnumeiro1", handle: null, url: "https://www.instagram.com/reel/FXitsnumeiro1/" });
eq("IG reels/ sem www", parsePostUrl("instagram", "https://instagram.com/reels/AbC_12-x")?.external_id, "AbC_12-x");
eq("IG p/", parsePostUrl("instagram", "https://www.instagram.com/p/AbCdE1/")?.url, "https://www.instagram.com/p/AbCdE1/");
eq("IG com utilizador", parsePostUrl("instagram", "https://www.instagram.com/ItsNumeiro/reel/AbCdE1/")?.handle, "itsnumeiro");
eq("IG perfil recusado", parsePostUrl("instagram", "https://www.instagram.com/itsnumeiro/"), null);
eq("IG stories recusado", parsePostUrl("instagram", "https://www.instagram.com/stories/x/123/"), null);
eq("IG outro domínio", parsePostUrl("instagram", "https://evil.com/reel/AbCdE1/"), null);
eq("IG domínio parecido", parsePostUrl("instagram", "https://www.instagram.com.evil.com/reel/AbCdE1/"), null);
eq("TikTok", parsePostUrl("tiktok", "https://www.tiktok.com/@ItsNumeiro/video/7301234567890123456?lang=pt"),
  { external_id: "7301234567890123456", handle: "itsnumeiro", url: "https://www.tiktok.com/@itsnumeiro/video/7301234567890123456" });
eq("TikTok curto recusado", parsePostUrl("tiktok", "https://vm.tiktok.com/ZMabc123/"), null);
eq("YT shorts", parsePostUrl("youtube", "https://youtube.com/shorts/dQw4w9WgXcQ?feature=share")?.external_id, "dQw4w9WgXcQ");
eq("YT watch com outros parâmetros", parsePostUrl("youtube", "https://www.youtube.com/watch?t=3&v=dQw4w9WgXcQ")?.url, "https://www.youtube.com/shorts/dQw4w9WgXcQ");
eq("YT youtu.be", parsePostUrl("youtube", "https://youtu.be/dQw4w9WgXcQ")?.external_id, "dQw4w9WgXcQ");
eq("YT ID curto", parsePostUrl("youtube", "https://youtu.be/curto"), null);
eq("IG noutra plataforma", parsePostUrl("youtube", "https://www.instagram.com/reel/FXitsnumeiro1/"), null);
eq("espaços no meio", parsePostUrl("instagram", "https://www.instagram.com/reel/AbC DE/"), null);
eq("problema: vazio não avisa", postUrlProblem("instagram", "  ", "itsnumeiro"), null);
eq("problema: outra conta", postUrlProblem("tiktok", "https://www.tiktok.com/@outra/video/7301234567890123456", "ItsNumeiro"),
  "Este link é de @outra, não de @ItsNumeiro.");
eq("problema: conta certa", postUrlProblem("tiktok", "https://www.tiktok.com/@itsnumeiro/video/7301234567890123456", "ItsNumeiro"), null);
console.log(`pub-url ${n - bad}/${n}`);
if (bad) process.exit(1);
