import 'package:flutter/material.dart';

import '../../../core/network/api_client.dart';
import '../../../core/services/group_ride_service.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  late var _request = GroupRideService.subscription();

  void _refresh() => setState(() => _request = GroupRideService.subscription());

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Subscription'), actions: [
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh subscription',
          ),
        ]),
        body: FutureBuilder<ApiResponse<RideSubscription>>(
          future: _request,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final result = snapshot.data;
            final plan = result?.data;
            if (plan == null) {
              return Center(
                child: TextButton(
                  onPressed: _refresh,
                  child: const Text('Could not load your plan. Try again'),
                ),
              );
            }
            final expires = plan.premiumUntil?.toLocal();
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Card(
                  child: ListTile(
                    leading: Icon(plan.premium
                        ? Icons.workspace_premium_outlined
                        : Icons.person_outline),
                    title: Text(plan.premium ? 'Premium active' : 'Free plan'),
                    subtitle: Text(plan.premium && expires != null
                        ? 'Ends ${MaterialLocalizations.of(context).formatMediumDate(expires)}'
                        : 'Premium access is currently granted by JustRide.'),
                  ),
                ),
                const ListTile(
                  leading: Icon(Icons.groups_outlined),
                  title: Text('Group Ride'),
                  subtitle: Text(
                      'Create or join private rides and see riders who choose to share their location.'),
                ),
              ],
            );
          },
        ),
      );
}
