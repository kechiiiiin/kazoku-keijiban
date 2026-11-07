import type { Sekisho } from "./auth.ts";

export interface Env {
  DB: D1Database;

  // ---- 認証（Access のサービストークン。JWT の検証は関所 sekisho に聞く・auth.ts） ----
  /** 関所への Service Binding。未設定なら全員 401 */
  SEKISHO?: Sekisho;
  /** Access アプリ kazoku-keijiban の AUD タグ（secret）。空なら全員 401 */
  CF_ACCESS_AUD?: string;
  /** 通すサービストークンの Client ID（カンマ区切り・secret）。**空なら1本も通さない** */
  ACCESS_SERVICE_CLIENT_IDS?: string;

  // ---- 家族 ----
  /** 押す人の候補（カンマ区切り・secret）。名前をソースに載せないため secret に置く。空なら書き込みは全部 400 */
  MEMBERS?: string;

  // ---- APNs（ウィジェット用プッシュ）。鍵が揃っていなければ送らない ----
  /** .p8 の中身（PEM・secret） */
  APNS_KEY?: string;
  /** 鍵の Key ID（secret） */
  APNS_KEY_ID?: string;
  /** Apple Developer の Team ID（secret） */
  APNS_TEAM_ID?: string;
  /** アプリの bundle id（vars）。apns-topic は `<これ>.push-type.widgets` */
  APNS_BUNDLE_ID?: string;
  /** "production"（TestFlight・App Store）か "development"（Xcode から入れた開発ビルド）。vars */
  APNS_ENV?: string;

  /** ローカル開発の迂回。ビルド時定数と localhost が揃わないと効かない（auth.ts） */
  DEV_BYPASS_AUTH?: string;
}

export type AppEnv = { Bindings: Env; Variables: { principal: string } };
