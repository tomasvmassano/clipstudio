import { ChannelBreakdownChart, type MixDatum } from "@/components/channel-breakdown-chart";
import { ConversationVolumeChart } from "@/components/conversation-volume-chart";
import { CsatResponsesChart, type ProdRow } from "@/components/csat-responses-chart";
import { FirstReplyTimeChart, type WeekRow } from "@/components/first-reply-time-chart";
import { RecentConversations } from "@/components/recent-conversations";
import { DashboardStats, type Stat } from "@/components/stats";
import { SupportActivity } from "@/components/support-activity";
import { TeamOnDuty } from "@/components/team-on-duty";
import type { Hoje } from "@/lib/hoje";
import type { Guiao } from "@/lib/types";

export type DashboardData = {
	today: string;
	stats: Stat[];
	hoje: Hoje;
	mix: MixDatum[];
	guioesHoje: Guiao[];
	prod: ProdRow[];
	semanas: WeekRow[];
};

/** Layout do efferd dashboard-3, com os dados do Estúdio. */
export function Dashboard({ data }: { data: DashboardData }) {
	return (
		<div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
			<DashboardStats stats={data.stats} />
			<ConversationVolumeChart rows={data.hoje.diario} today={data.today} />
			<ChannelBreakdownChart data={data.mix} total={data.guioesHoje.filter((g) => g.status !== "rejeitado").length} />
			<CsatResponsesChart rows={data.prod} />
			<FirstReplyTimeChart rows={data.semanas} />
			<TeamOnDuty agentes={data.hoje.agentes} />
			<RecentConversations guioes={data.guioesHoje} />
			<SupportActivity items={data.hoje.atividade} />
		</div>
	);
}
