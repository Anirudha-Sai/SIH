import 'package:flutter/material.dart';

class TrackingCard extends StatelessWidget {
  final List<String> routes;
  final Set<String> activeRoutes;
  final String? selectedRoute;
  final Function(String?) onRouteChanged;
  final Function() onFindDistance;
  final Function() onHideCard;
  final String distanceTimeText;
  final String lastUpdatedText;
  
  const TrackingCard({
    super.key,
    required this.routes,
    required this.activeRoutes,
    required this.selectedRoute,
    required this.onRouteChanged,
    required this.onFindDistance,
    required this.onHideCard,
    required this.distanceTimeText,
    required this.lastUpdatedText,
  });
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 12,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header with title and close button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Select a route to start tracking',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.grey),
                onPressed: onHideCard,
                splashRadius: 20,
              ),
            ],
          ),
          const SizedBox(height: 10),
          
          // Route dropdown
          DropdownButtonFormField<String>(
            value: selectedRoute,
            hint: const Text('-- Select Route --'),
            isExpanded: true,
            items: routes.map((route) {
              final isActive = activeRoutes.contains(route);
              return DropdownMenuItem(
                value: route,
                child: Text(
                  isActive ? '$route 🟢' : route,
                  style: TextStyle(
                    color: isActive ? Colors.green : Colors.black,
                  ),
                ),
              );
            }).toList(),
            onChanged: onRouteChanged,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 15),
            ),
          ),
          
          const SizedBox(height: 10),
          
          // Find distance button
          if (selectedRoute != null && selectedRoute!.isNotEmpty)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: onFindDistance,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                  child: const Text(
                    '📏 Find Distance',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          
          const SizedBox(height: 10),
          
          // Distance and time info
          if (distanceTimeText.isNotEmpty)
            Text(
              distanceTimeText,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          
          // Last updated info
          if (lastUpdatedText.isNotEmpty)
            Text(
              lastUpdatedText,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
        ],
      ),
    );
  }
}
